"""Link cleaning / embed-fixing logic, ported from main-site/script.js and
main-site/api/resolve.js so the bot behaves identically to the web app.
"""
from __future__ import annotations

import ipaddress
import re
import socket
from dataclasses import dataclass, field
from urllib.parse import urlsplit, urlunsplit, parse_qsl, quote

import aiohttp

# ===== TRACKING PARAMETERS =====
# Any parameter whose name starts with one of these prefixes is a tracker, on
# every host. Catches the long tail of UTM variants (utm_creative,
# utm_pubreferrer, utm_swu, utm_brand, ...) that an exact-name list misses, plus
# Branch.io's attribution blobs (_branch_match_id, _branch_referrer, ...) which
# apps bolt onto otherwise clean deep links.
TRACKER_PREFIXES = ('utm_', '_branch_')

# Keys are compared lowercased, so every entry below must be lowercase.
UNIVERSAL_TRACKERS = {
    # UTM (the utm_ prefix rule above covers the rest)
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    'utm_id', 'utm_reader', 'utm_name', 'utm_social', 'utm_social-type',
    # Click IDs
    'fbclid', 'gclid', 'gclsrc', 'msclkid', 'dclid', 'yclid', 'twclid', 'mc_eid',
    'igshid', 'igsh', 'igsi', 'li_fat_id', 'ttclid', 'sccid', 's_cid', 'snkrhsp',
    # Google Ads auto-tagging
    'gad_source', 'gad_campaignid',
    # General
    'ref', 'ref_src', 'ref_url', 'referral', 'source', 'srsltid',
    'icid', 'cid', 'eid', 'pid', 'sid', 'rid', 'uid', 'vid',
    '_ga', '_gl', '_hsenc', '_hsmi', 'hsa_acc', 'hsa_ad', 'hsa_cam', 'hsa_grp',
    'hsa_kw', 'hsa_mt', 'hsa_net', 'hsa_src', 'hsa_tgt', 'hsa_ver',
    'mibextid', 'mbid', 'ml_subscriber', 'ml_subscriber_hash',
    'wt.mc_id', 'wt.srch', 'affiliate', 'aff_id', 'aff_sub',
    'trk', 'track', 'tracking', 'trksid', 'tracesourcecode',
    # AMP page selector. Not tracking - it picks Google's stripped-down mobile
    # rendering - but the canonical page is what should be shared, and AMP is
    # deprecated. Dropping it redirects to the real article.
    'amp',
    # Google app share tag, e.g. shem=...,sh/x/discover/m1/4 on links shared
    # from Discover. The app adds it to whatever page was shared, not just
    # Google's own.
    'shem',
    # Klaviyo
    '_kx', 'kx', 'tw_source',
    # Triple Whale ad attribution (Shopify stores)
    'tw_adid', 'tw_campaign', 'tw_kwdid',
    # Branch.io attribution keys that don't carry the _branch_ prefix. The
    # routing params ($deeplink_path, $fallback_url, $ios_url, ...) are left
    # alone - those decide where the link actually goes.
    '~channel', '~feature', '~campaign', '~tags', '~stage', '~creation_source',
    '~click_id', '~referring_link', '~id', '~secondary_publisher',
    '$3p', '$original_url', '$identity_id', '$s2s',
}

PLATFORM_TRACKERS = {
    'twitter.com': {'s', 't', 'a', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
                     'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url'},
    'x.com': {'s', 't', 'a', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
              'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url'},
    'instagram.com': {'igshid', 'igsh', 'igsi', 'ig_rid', 'ig_mid', 'stp', 'smid', 'hl',
                       'taken-by'},
    'facebook.com': {'__cft__', '__tn__', '__xts__', 'hc_ref', 'fref', 'rc',
                      'theater', 'refsrc', 'source', '_rdr',
                      'referral_source', 'surface_type', 'in_reels_tab_context'},
    'fb.com': {'__cft__', '__tn__', '__xts__', 'hc_ref', 'fref', 'rc',
               'theater', 'refsrc', 'source', '_rdr',
               'referral_source', 'surface_type', 'in_reels_tab_context'},
    'youtube.com': {'feature', 'app', 'list', 'index', 'pp', 'si', 'is', 'ab_channel',
                     'cbrd', 'ucbcb', 'pbc', 'pbj'},
    'youtu.be': {'feature', 'si', 'is'},
    'tiktok.com': {'_d', 'checksum', 'is_copy_url', 'is_from_webapp',
                    'sender_device', 'sender_web_id', 'share_app_id', 'share_link_id',
                    'tt_from', 'tt_medium', 'tt_campaign', 'tiktok_share_from',
                    'source_ref', 'sec_uid', '_r'},
    'reddit.com': {'utm_name', 'ref_source', 'ref', 'context', 'share_id',
                    'post_fullname', 'cid', 'subreddit_id', 'post_index'},
    'linkedin.com': {'trk', 'trkinfo', 'trk_sid', 'originalsubdomain', 'refid',
                      'lipi', 'licu', 'lici', 'sharer', 'trackingid', 'rcm'},
    'amazon.com': {'ref', 'ref_', 'pf_rd_r', 'pf_rd_p', 'pf_rd_i', 'pf_rd_m', 'pf_rd_s', 'pf_rd_t',
                    'pd_rd_r', 'pd_rd_w', 'pd_rd_wg', '_encoding', 'smid', 'sprefix', 'sr',
                    'ie', 'qid', 'rps', 'linkcode', 'linkid', 'ascsubtag', 'tag',
                    'creative', 'creativeasin'},
    'google.com': {'ved', 'usg', 'ei', 'sei', 'sa', 'sqi', 'sourceid',
                    'client', 'channel', 'rlz', 'oq'},
    'substack.com': {'r', 'utm_source', 'utm_medium', 'utm_campaign', 'publication_id', 'post_id'},
    'github.com': {'ref', 'notification_referrer_id', 'bpo'},
    'discord.com': {'ref', 'source'},
    'pinterest.com': {'sent_episod', 'nic'},
    'snapchat.com': {'sc_referrer', 'share_id'},
    'ebay.com': {'mkevt', 'mkcid', 'mkrid', 'campid', 'toolid', 'customid',
                  'epid', 'hash', '_trkparms', '_trksid'},
    'aliexpress.com': {'aff_platform', 'aff_trace_key', 'terminal_id', 'biztype', 'sourcetype',
                         'btsid', 'ws_ab_test', 'initiative_id', 'origin_design_token'},
    'spotify.com': {'si', 'context', 'nd'},
    'threads.net': {'igshid', 'igsh', 'igsi', 'mibextid', 'xmt', 'slof'},
    'threads.com': {'igshid', 'igsh', 'igsi', 'mibextid', 'xmt', 'slof'},
    'twitch.tv': {'tt_content', 'tt_medium', 'sr', 'filter', 'referrer'},
    'pixiv.net': {'lang'},
    'tumblr.com': {'is_related_post', 'source'},
    'bilibili.com': {'spm_id_from', 'vd_source', 'from_source', 'share_source',
                      'share_medium', 'share_plat', 'share_session_id', 'share_tag',
                      'timestamp', 'unique_k', 'bbid', 'ts'},
    'bsky.app': {'ref_src', 'ref_url'},
    # Eightfold career sites (<tenant>.eightfold.ai/careers/job/<id>) tack on
    # the tenant's own domain and a UI locale; the subdomain already picks the
    # tenant and the posting lives at its path.
    'eightfold.ai': {'domain', 'hl'},
    # Samsung Community (Khoros forums on regional subdomains such as
    # r1.community.samsung.com) tags shared posts with src=ShareByUserCM.
    # Scoped to the forums: src is too generic a name to strip everywhere.
    'community.samsung.com': {'src'},
}

# Platform trackers matched by shape instead of by name, for keys a platform
# rotates faster than a list can keep up. Tested against the lowercased key.
# Every host here must also be a PLATFORM_TRACKERS key, which picks the platform.
PLATFORM_TRACKER_PATTERNS = {
    # Instagram share links carry a random four-letter key (stkn, psln, dlrf,
    # ...) that changes every few weeks. ?next= on the login page is the only
    # four-letter parameter an Instagram link needs.
    'instagram.com': re.compile(r'^(?!next$)[a-z]{4}$'),
}

# ===== FULL QUERY-STRIP HOSTS =====
# Workday job postings (<tenant>.wdN.myworkdayjobs.com/<locale>/<site>/job/...,
# plus the myworkdaysite.com variant) carry whatever search facets the sharer
# happened to have selected - timeType, locationCountry, and jobFamilyGroup
# repeated once per checked box - and the facet names are defined per tenant,
# so no fixed list keeps up with them. The posting is addressed entirely by its
# path, so the whole query string goes. Only /job/ pages qualify: on the search
# listing above them those same params ARE the search.
STRIP_ALL_PARAMETER_HOSTS = ('myworkdayjobs.com', 'myworkdaysite.com')
STRIP_ALL_PARAMETER_PATH = '/job/'

PLATFORM_LABELS = {
    'twitter.com': 'X / Twitter', 'x.com': 'X / Twitter',
    'instagram.com': 'Instagram', 'tiktok.com': 'TikTok', 'reddit.com': 'Reddit',
    'youtube.com': 'YouTube', 'youtu.be': 'YouTube',
    'facebook.com': 'Facebook', 'fb.com': 'Facebook', 'linkedin.com': 'LinkedIn',
    'amazon.com': 'Amazon', 'substack.com': 'Substack', 'github.com': 'GitHub',
    'discord.com': 'Discord', 'pinterest.com': 'Pinterest', 'snapchat.com': 'Snapchat',
    'spotify.com': 'Spotify', 'ebay.com': 'eBay', 'aliexpress.com': 'AliExpress',
    'threads.net': 'Threads', 'threads.com': 'Threads', 'bsky.app': 'Bluesky',
    'twitch.tv': 'Twitch', 'pixiv.net': 'Pixiv', 'tumblr.com': 'Tumblr',
    'bilibili.com': 'BiliBili', 'deviantart.com': 'DeviantArt',
    'newgrounds.com': 'Newgrounds', 'furaffinity.net': 'Fur Affinity',
    'google.com': 'Google',
    'myworkdayjobs.com': 'Workday', 'myworkdaysite.com': 'Workday',
    'eightfold.ai': 'Eightfold',
    'community.samsung.com': 'Samsung Community',
}

# Mastodon has no single hostname, so instances have to be enumerated. This is
# the set FxMastodon covers.
MASTODON_INSTANCES = (
    'mastodon.social', 'mstdn.jp', 'mastodon.cloud', 'mstdn.social',
    'mastodon.world', 'mastodon.online', 'mas.to', 'techhub.social',
    'mastodon.uno', 'infosec.exchange',
)


# ===== BARE-HOSTNAME RECOGNITION =====
# A scheme is optional when sharing a link, so "youtube.com/watch?v=..." has to
# be recognised as a URL and https:// added. The catch is that prose looks the
# same to a naive parser: without a check, "how are you" became
# "https://how are you" and "not a link." became "https://not a link.".
#
# The test is on the hostname alone: labels separated by dots, ending in a TLD
# of at least two letters. That accepts anything actually resolvable and
# rejects ordinary words, which have no dot, and sentences, which have spaces.
_HOSTNAME_PATTERN = re.compile(
    r'^(?=.{1,253}$)'
    r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+'  # one or more labels
    r'[a-z]{2,63}$',                                 # TLD
    re.I,
)

# Hosts that are valid but can't be a shared link's destination on their own.
# A bare IP is left to the scheme-prefixed path so a typo'd version number
# ("1.2.3.4") isn't treated as a link.
_IPV4_PATTERN = re.compile(r'^\d{1,3}(?:\.\d{1,3}){3}$')

# Filenames mentioned in chat ("open notes.txt", "see report.pdf") parse as a
# host with a letters-only TLD, so the common extensions are excluded. Only
# applies without a scheme - "https://foo.zip" is still a link.
_FILE_EXTENSIONS = frozenset((
    'txt', 'md', 'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'csv',
    'json', 'yaml', 'yml', 'toml', 'xml', 'html', 'htm', 'css', 'js', 'ts',
    'jsx', 'tsx', 'py', 'rb', 'rs', 'go', 'java', 'c', 'cpp', 'h', 'cs',
    'sh', 'bat', 'ps1', 'sql', 'log', 'ini', 'cfg', 'conf', 'env', 'lock',
    'png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'ico', 'bmp', 'mp3', 'mp4',
    'wav', 'mov', 'avi', 'mkv', 'webm', 'zip', 'gz', 'tar', 'rar', '7z',
    'exe', 'dll', 'app', 'dmg', 'iso', 'bin', 'db', 'bak', 'tmp',
))


def hostname_of(url_parts) -> str:
    """The hostname of a urlsplit() result, or '' when it has none."""
    hostname = url_parts.hostname
    if not hostname:
        return ''
    return hostname


def _is_valid_hostname(hostname: str, *, has_path: bool = False) -> bool:
    """Whether a scheme-less input's hostname really looks like a link's host
    (dotted labels ending in a letters-only TLD, not a bare IP or filename)."""
    if not hostname or _IPV4_PATTERN.match(hostname):
        return False
    if not _HOSTNAME_PATTERN.match(hostname):
        return False
    # Several file extensions are also real TLDs (.app, .zip, .dev, .sh), so
    # the exclusion only applies to a bare host. With a path attached it's
    # unambiguously a link - a filename doesn't carry one.
    if has_path:
        return True
    top_level_domain = hostname.rsplit('.', 1)[-1].lower()
    return top_level_domain not in _FILE_EXTENSIONS


def _is_tracker_parameter(key: str, platform_set: set[str] | None,
                          platform_pattern: re.Pattern | None = None) -> bool:
    """Matching is always case-insensitive: query keys arrive in whatever case
    the sharing app produced (?UTM_Source=..., ?FBCLID=...), and those are the
    same tracker."""
    lowercase_key = key.lower()
    if lowercase_key.startswith(TRACKER_PREFIXES):
        return True
    if lowercase_key in UNIVERSAL_TRACKERS:
        return True
    if platform_pattern and platform_pattern.match(lowercase_key):
        return True
    if platform_set and lowercase_key in platform_set:
        return True
    return False


def _match_host(hostname: str, key: str) -> bool:
    return hostname == key or hostname.endswith('.' + key)


def _strips_all_parameters(hostname: str, path: str) -> bool:
    if STRIP_ALL_PARAMETER_PATH not in path:
        return False
    for strip_host in STRIP_ALL_PARAMETER_HOSTS:
        if _match_host(hostname, strip_host):
            return True
    return False


def _embed_converters():
    """Builds the EMBED_CONVERTERS table: one (platform name, hosts, convert)
    entry per platform with an embed-friendly mirror. Each convert function
    takes the lowercased host and the path and returns the (host, path) the
    cleaned link should use - unchanged when the page needs no embed fix."""
    def twitter(host, path):
        match = re.match(r'^/[^/]+/(status/\d+)$', path)
        if match:
            path = '/i/' + match.group(1)
        return 'fixupx.com', path

    def instagram(host, path):
        return 'www.oginstagram.com', path

    def youtube(host, path):
        # Only Shorts need an embed fix - regular watch links already preview
        # fine, so leave them on youtube.com.
        if path.startswith('/shorts/'):
            return 'koutube.com', path
        return host, path

    def tiktok(host, path):
        # Preserve the subdomain so vm./vt. share links keep resolving on the
        # matching tnktok.com subdomain.
        if host.startswith('www.'):
            host = host[4:]
        return host.replace('tiktok.com', 'tnktok.com'), path

    def facebook(host, path):
        return 'www.facebed.com', path

    def reddit(host, path):
        return 'www.vxreddit.com', path

    def discord_canary(host, path):
        return 'discord.com', path

    def threads(host, path):
        return 'fixthreads.seria.moe', path

    def bluesky(host, path):
        return 'fxbsky.app', path

    def twitch(host, path):
        return 'fxtwitch.seria.moe', path

    def spotify(host, path):
        # Album and prerelease pages render fine on their own, so leave those
        # on spotify.com.
        if re.match(r'^(/intl-[^/]+)?/(album|prerelease)/', path):
            return host, path
        return 'fxspotify.com', path

    def pixiv(host, path):
        return 'phixiv.net', path

    def tumblr(host, path):
        return 'tpmblr.com', path

    def bilibili(host, path):
        return 'vxbilibili.com', path

    def deviantart(host, path):
        # fixDeviantArt only handles deviation and journal pages; a profile or
        # gallery link would 404 there, so leave those on deviantart.com.
        if re.match(r'^/[^/]+/(art|journal)/[^/]+', path):
            return 'fixdeviantart.com', path
        return host, path

    def newgrounds(host, path):
        # FixNewgrounds covers art pages only.
        if re.match(r'^/art/view/[^/]+/[^/]+', path):
            return 'fixnewgrounds.com', path
        return host, path

    def furaffinity(host, path):
        # xfuraffinity covers submission pages only.
        if re.match(r'^/view/[^/]+', path):
            return 'xfuraffinity.net', path
        return host, path

    def mastodon(host, path):
        # FxMastodon isn't a plain host swap - the instance becomes the first
        # path segment: fx.zillanlabs.tech/mastodon.social/@user/12345
        if host.startswith('www.'):
            instance = host[4:]
        else:
            instance = host
        if re.match(r'^/@[^/]+/[^/]+', path):
            return 'fx.zillanlabs.tech', '/' + instance + path
        return host, path

    mastodon_hosts = set(MASTODON_INSTANCES)
    for instance in MASTODON_INSTANCES:
        mastodon_hosts.add('www.' + instance)

    return [
        ('X / Twitter', {'x.com', 'twitter.com', 'www.x.com', 'www.twitter.com'}, twitter),
        ('Instagram', {'instagram.com', 'www.instagram.com'}, instagram),
        ('YouTube', {'youtube.com', 'www.youtube.com', 'm.youtube.com'}, youtube),
        ('TikTok', {'tiktok.com', 'www.tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com'}, tiktok),
        ('Facebook', {'facebook.com', 'www.facebook.com', 'fb.com', 'www.fb.com', 'm.facebook.com'}, facebook),
        ('Reddit', {'reddit.com', 'www.reddit.com', 'old.reddit.com', 'new.reddit.com'}, reddit),
        ('Discord', {'canary.discord.com', 'ptb.discord.com'}, discord_canary),
        ('Threads', {'threads.net', 'www.threads.net', 'threads.com', 'www.threads.com'}, threads),
        ('Bluesky', {'bsky.app', 'www.bsky.app'}, bluesky),
        ('Twitch', {'twitch.tv', 'www.twitch.tv', 'm.twitch.tv'}, twitch),
        ('Spotify', {'open.spotify.com', 'spotify.com', 'www.spotify.com'}, spotify),
        ('Pixiv', {'pixiv.net', 'www.pixiv.net'}, pixiv),
        ('Tumblr', {'tumblr.com', 'www.tumblr.com'}, tumblr),
        ('BiliBili', {'bilibili.com', 'www.bilibili.com', 'm.bilibili.com'}, bilibili),
        ('DeviantArt', {'deviantart.com', 'www.deviantart.com'}, deviantart),
        ('Newgrounds', {'newgrounds.com', 'www.newgrounds.com'}, newgrounds),
        ('Fur Affinity', {'furaffinity.net', 'www.furaffinity.net'}, furaffinity),
        ('Mastodon', mastodon_hosts, mastodon),
    ]


EMBED_CONVERTERS = _embed_converters()


@dataclass
class Change:
    type: str
    label: str


@dataclass
class CleanResult:
    cleaned: str
    changes: list[Change] = field(default_factory=list)
    platform: str = 'General'
    was_converted: bool = False


class InvalidUrlError(ValueError):
    pass


def detect_platform(hostname: str) -> str | None:
    for key, label in PLATFORM_LABELS.items():
        if _match_host(hostname, key):
            return label
    if hostname in MASTODON_INSTANCES:
        return 'Mastodon'
    return None


def _extract_google_destination(query_pairs: list[tuple[str, str]]) -> str | None:
    query = dict(query_pairs)
    destination = query.get('url')
    if not destination:
        destination = query.get('q')
    if not destination:
        return None
    try:
        parts = urlsplit(destination)
        if parts.scheme in ('http', 'https') and parts.netloc:
            return destination
    except ValueError:
        pass
    return None


def clean_url(raw_input: str) -> CleanResult:
    """Cleans one shared link: adds https:// to a bare host, normalizes
    YouTube hosts, unwraps Google redirect links, strips tracking parameters,
    swaps in an embed-friendly domain where one exists, and labels the
    platform. Raises InvalidUrlError when the input isn't a usable link."""
    text = raw_input.strip()
    if not text:
        raise InvalidUrlError('Please enter a URL.')

    had_scheme = bool(re.match(r'^https?://', text, re.I))
    if had_scheme:
        candidate = text
    else:
        candidate = 'https://' + text
    try:
        parts = urlsplit(candidate)
    except ValueError:
        raise InvalidUrlError("That doesn't look like a link.")

    if parts.scheme not in ('http', 'https') or not parts.netloc:
        raise InvalidUrlError("That doesn't look like a link.")

    # Without a scheme the input could just as easily be prose, so the
    # hostname has to actually look like one before https:// is assumed.
    if not had_scheme:
        has_path = bool(parts.path.strip('/') or parts.query or parts.fragment)
        if not _is_valid_hostname(hostname_of(parts), has_path=has_path):
            raise InvalidUrlError("That doesn't look like a link.")

    full_host = hostname_of(parts)
    full_host_lowercase = full_host.lower()
    if full_host_lowercase.startswith('www.'):
        hostname = full_host_lowercase[4:]
    else:
        hostname = full_host_lowercase
    changes: list[Change] = []

    query_pairs = parse_qsl(parts.query, keep_blank_values=True)

    # 0. Normalize youtu.be -> youtube.com for consistency
    if hostname == 'youtu.be':
        video_id = parts.path.strip('/')
        if video_id:
            normalized_pairs = [('v', video_id)]
            for key, value in query_pairs:
                if key.lower() != 'v':
                    normalized_pairs.append((key, value))
            query_pairs = normalized_pairs
            full_host_lowercase = 'www.youtube.com'
            hostname = 'youtube.com'
            parts = parts._replace(path='/watch')
            changes.append(Change('embed', 'Converted youtu.be to youtube.com'))

    # 0b. Normalize the mobile YouTube host so links open the full site
    if full_host_lowercase == 'm.youtube.com':
        full_host_lowercase = 'www.youtube.com'
        hostname = 'youtube.com'
        changes.append(Change('embed', 'Converted m.youtube.com to www.youtube.com'))

    # 1. Google Search - extract destination
    if hostname == 'google.com' or hostname.endswith('.google.com'):
        destination = _extract_google_destination(query_pairs)
        if destination:
            changes.append(Change('redirect', 'Extracted destination from Google Search'))
            return CleanResult(cleaned=destination, changes=changes, platform='Google Search', was_converted=False)

    # 2. Remove platform-specific + universal trackers
    platform_key = None
    for tracker_host in PLATFORM_TRACKERS:
        if _match_host(hostname, tracker_host):
            platform_key = tracker_host
            break
    platform_set = None
    platform_pattern = None
    if platform_key:
        platform_set = PLATFORM_TRACKERS.get(platform_key)
        platform_pattern = PLATFORM_TRACKER_PATTERNS.get(platform_key)
    strip_all_parameters = _strips_all_parameters(hostname, parts.path)

    kept_pairs = []
    removed_keys = []
    for key, value in query_pairs:
        if strip_all_parameters or _is_tracker_parameter(key, platform_set, platform_pattern):
            removed_keys.append(key)
        else:
            kept_pairs.append((key, value))

    if removed_keys:
        if len(removed_keys) > 1:
            plural_suffix = 's'
        else:
            plural_suffix = ''
        changes.append(Change('trackers', f'Removed {len(removed_keys)} tracker{plural_suffix}'))

    # 3. Embed conversion
    converted_platform = None
    new_host = full_host_lowercase
    new_path = parts.path
    for name, hosts, convert in EMBED_CONVERTERS:
        if full_host_lowercase in hosts:
            host_before = new_host
            new_host, new_path = convert(full_host_lowercase, parts.path)
            if new_host != host_before:
                changes.append(Change('embed', f'Converted to embed-friendly domain ({new_host})'))
                converted_platform = name
            break

    # 4. Platform label
    if converted_platform:
        platform_label = converted_platform
    else:
        platform_label = detect_platform(hostname)
        if not platform_label:
            platform_label = 'General'

    # 5. Rebuild URL
    encoded_pairs = []
    for key, value in kept_pairs:
        encoded_pairs.append(f'{quote(key, safe="")}={quote(value, safe="")}')
    new_query = '&'.join(encoded_pairs)
    # Keep the fragment: it's the anchor the sharer picked (a Reddit comment,
    # a docs heading, a video timestamp), not tracking.
    cleaned = urlunsplit((parts.scheme, new_host, new_path, new_query, parts.fragment))
    if cleaned.endswith('?'):
        cleaned = cleaned[:-1]

    if not changes:
        changes.append(Change('clean', 'URL was already clean'))

    return CleanResult(
        cleaned=cleaned,
        changes=changes,
        platform=platform_label,
        was_converted=converted_platform is not None,
    )


# ===== REDIRECT / TITLE RESOLUTION =====

_PRIVATE_NETWORKS = True  # marker; real check done via ipaddress below

_TITLE_PATTERN = re.compile(rb'<title[^>]*>([^<]*)</title>', re.I)

_USER_AGENT = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
)


def _is_blocked_host(hostname: str) -> bool:
    """Whether a host must not be fetched: empty, localhost, or an IP address
    (given directly or resolved via DNS) that isn't on the public internet."""
    if not hostname:
        return True
    lowercase_host = hostname.lower()
    if lowercase_host == 'localhost' or lowercase_host.endswith('.localhost'):
        return True
    try:
        address = ipaddress.ip_address(lowercase_host)
        return (address.is_private or address.is_loopback or address.is_link_local
                or address.is_reserved or address.is_multicast)
    except ValueError:
        pass
    # Resolve the hostname and reject if it lands on a non-public address
    # (covers 127/8, RFC1918 ranges, link-local incl. the 169.254.169.254
    # cloud metadata endpoint, etc.) so the bot can't be used to probe the
    # VPS's internal network via a crafted /fix link.
    try:
        address_infos = socket.getaddrinfo(lowercase_host, None)
    except socket.gaierror:
        return False
    for address_info in address_infos:
        address_text = address_info[4][0]
        try:
            address = ipaddress.ip_address(address_text)
        except ValueError:
            continue
        if (address.is_private or address.is_loopback or address.is_link_local
                or address.is_reserved or address.is_multicast):
            return True
    return False


async def resolve_url(session: aiohttp.ClientSession, url: str) -> dict:
    """Follows redirects and extracts a page title, mirroring main-site/api/resolve.js."""
    parts = urlsplit(url)
    if parts.scheme not in ('http', 'https') or _is_blocked_host(hostname_of(parts)):
        return {'final_url': None, 'title': None}

    hostname = hostname_of(parts).lower()
    is_youtube = hostname == 'youtube.com' or hostname.endswith('.youtube.com') or hostname == 'youtu.be'

    timeout = aiohttp.ClientTimeout(total=10)
    headers = {
        'User-Agent': _USER_AGENT,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
    }

    try:
        async with session.get(url, headers=headers, timeout=timeout, allow_redirects=True, max_redirects=10) as response:
            final_url = str(response.url)
            title = None

            if is_youtube:
                final_host = hostname_of(urlsplit(final_url)).lower().removeprefix('www.')
                if final_host != 'youtube.com' and 'youtu.be' not in final_url:
                    final_url = url
                try:
                    oembed_url = f'https://www.youtube.com/oembed?url={final_url}&format=json'
                    async with session.get(oembed_url, timeout=aiohttp.ClientTimeout(total=8)) as oembed_response:
                        if oembed_response.ok:
                            data = await oembed_response.json(content_type=None)
                            title = data.get('title')
                except Exception:
                    pass
            else:
                content_type = response.headers.get('content-type', '')
                if 'text/html' in content_type:
                    body = await response.content.read(20000)
                    match = _TITLE_PATTERN.search(body)
                    if match:
                        title = match.group(1).decode('utf-8', 'ignore').strip()
                        if not title:
                            title = None

            return {'final_url': final_url, 'title': title}
    except Exception:
        return {'final_url': None, 'title': None}

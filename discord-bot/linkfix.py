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
UNIVERSAL_TRACKERS = {
    # UTM
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    'utm_id', 'utm_reader', 'utm_name', 'utm_social', 'utm_social-type',
    # Click IDs
    'fbclid', 'gclid', 'gclsrc', 'msclkid', 'dclid', 'yclid', 'twclid', 'mc_eid',
    'igshid', 'igsh', 'li_fat_id', 'ttclid', 'sccid', 's_cid', 'snkrhsp',
    # General
    'ref', 'ref_src', 'ref_url', 'referral', 'source', 'srsltid',
    'icid', 'cid', 'eid', 'pid', 'sid', 'rid', 'uid', 'vid',
    '_ga', '_gl', '_hsenc', '_hsmi', 'hsa_acc', 'hsa_ad', 'hsa_cam', 'hsa_grp',
    'hsa_kw', 'hsa_mt', 'hsa_net', 'hsa_src', 'hsa_tgt', 'hsa_ver',
    'mibextid', 'mbid', 'ml_subscriber', 'ml_subscriber_hash',
    'wt.mc_id', 'wt.srch', 'affiliate', 'aff_id', 'aff_sub',
    'trk', 'track', 'tracking', 'trksid',
    # Klaviyo
    '_kx', 'kx', 'tw_source',
}

PLATFORM_TRACKERS = {
    'twitter.com': {'s', 't', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
                     'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url'},
    'x.com': {'s', 't', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
              'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url'},
    'instagram.com': {'igshid', 'igsh', 'ig_rid', 'ig_mid', 'stp', 'smid', 'hl',
                       'img_index', 'taken-by'},
    'facebook.com': {'__cft__', '__tn__', '__xts__', 'hc_ref', 'fref', 'rc',
                      'theater', 'refsrc', 'source', '_rdr'},
    'fb.com': {'__cft__', '__tn__', '__xts__'},
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
    'pinterest.com': {'sent_episod', 'amp', 'nic'},
    'snapchat.com': {'sc_referrer', 'share_id'},
    'ebay.com': {'mkevt', 'mkcid', 'mkrid', 'campid', 'toolid', 'customid',
                  'epid', 'hash', '_trkparms', '_trksid'},
    'aliexpress.com': {'aff_platform', 'aff_trace_key', 'terminal_id', 'biztype', 'sourcetype',
                         'btsid', 'ws_ab_test', 'initiative_id', 'origin_design_token'},
    'spotify.com': {'si', 'context', 'nd'},
    'threads.net': {'igshid', 'mibextid', 'xmt', 'slof'},
    'threads.com': {'igshid', 'mibextid', 'xmt', 'slof'},
}

PLATFORM_LABELS = {
    'twitter.com': 'X / Twitter', 'x.com': 'X / Twitter',
    'instagram.com': 'Instagram', 'tiktok.com': 'TikTok', 'reddit.com': 'Reddit',
    'youtube.com': 'YouTube', 'youtu.be': 'YouTube',
    'facebook.com': 'Facebook', 'fb.com': 'Facebook', 'linkedin.com': 'LinkedIn',
    'amazon.com': 'Amazon', 'substack.com': 'Substack', 'github.com': 'GitHub',
    'discord.com': 'Discord', 'pinterest.com': 'Pinterest', 'snapchat.com': 'Snapchat',
    'spotify.com': 'Spotify', 'ebay.com': 'eBay', 'aliexpress.com': 'AliExpress',
    'threads.net': 'Threads', 'threads.com': 'Threads', 'bsky.app': 'Bluesky', 'google.com': 'Google',
}


def _match_host(hostname: str, key: str) -> bool:
    return hostname == key or hostname.endswith('.' + key)


def _embed_converters():
    def twitter(host, path):
        m = re.match(r'^/[^/]+/(status/\d+)$', path)
        if m:
            path = '/i/' + m.group(1)
        return 'fixupx.com', path

    def instagram(host, path):
        return 'kkclip.com', path

    def tiktok(host, path):
        if host in ('vm.tiktok.com', 'vt.tiktok.com'):
            return 'vt.kktiktok.com', path
        return 'kktiktok.com', path

    def facebook(host, path):
        return 'www.facebed.com', path

    def reddit(host, path):
        return 'www.vxreddit.com', path

    def discord_canary(host, path):
        return 'discord.com', path

    def threads(host, path):
        return host, path  # no reliable embed fix; tracker stripping only

    return [
        ('X / Twitter', {'x.com', 'twitter.com', 'www.x.com', 'www.twitter.com'}, twitter),
        ('Instagram', {'instagram.com', 'www.instagram.com'}, instagram),
        ('TikTok', {'tiktok.com', 'www.tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com'}, tiktok),
        ('Facebook', {'facebook.com', 'www.facebook.com', 'fb.com', 'www.fb.com', 'm.facebook.com'}, facebook),
        ('Reddit', {'reddit.com', 'www.reddit.com', 'old.reddit.com', 'new.reddit.com'}, reddit),
        ('Discord', {'canary.discord.com', 'ptb.discord.com'}, discord_canary),
        ('Threads', {'threads.net', 'www.threads.net', 'threads.com', 'www.threads.com'}, threads),
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
    return None


def _extract_google_dest(query_pairs: list[tuple[str, str]]) -> str | None:
    q = dict(query_pairs)
    dest = q.get('url') or q.get('q')
    if not dest:
        return None
    try:
        parts = urlsplit(dest)
        if parts.scheme in ('http', 'https') and parts.netloc:
            return dest
    except ValueError:
        pass
    return None


def clean_url(raw_input: str) -> CleanResult:
    text = raw_input.strip()
    if not text:
        raise InvalidUrlError('Please enter a URL.')

    candidate = text if re.match(r'^https?://', text, re.I) else 'https://' + text
    parts = urlsplit(candidate)

    if parts.scheme not in ('http', 'https') or not parts.netloc:
        raise InvalidUrlError("That doesn't look like a valid URL. Please include https://")

    full_host = parts.hostname or ''
    full_host_l = full_host.lower()
    hostname = full_host_l[4:] if full_host_l.startswith('www.') else full_host_l
    changes: list[Change] = []

    query_pairs = parse_qsl(parts.query, keep_blank_values=True)

    # 0. Normalize youtu.be -> youtube.com for consistency
    if hostname == 'youtu.be':
        video_id = parts.path.strip('/')
        if video_id:
            query_pairs = [('v', video_id)] + [(k, v) for k, v in query_pairs if k.lower() != 'v']
            full_host_l = 'www.youtube.com'
            hostname = 'youtube.com'
            parts = parts._replace(path='/watch')
            changes.append(Change('embed', 'Converted youtu.be to youtube.com'))

    # 1. Google Search - extract destination
    if hostname == 'google.com' or hostname.endswith('.google.com'):
        dest = _extract_google_dest(query_pairs)
        if dest:
            changes.append(Change('redirect', 'Extracted destination from Google Search'))
            return CleanResult(cleaned=dest, changes=changes, platform='Google Search', was_converted=False)

    # 2. Remove platform-specific + universal trackers
    platform_key = next((k for k in PLATFORM_TRACKERS if _match_host(hostname, k)), None)
    platform_set = PLATFORM_TRACKERS.get(platform_key) if platform_key else None

    kept_pairs = []
    removed = []
    for key, value in query_pairs:
        lower = key.lower()
        if lower in UNIVERSAL_TRACKERS or (platform_set and lower in platform_set):
            removed.append(key)
        else:
            kept_pairs.append((key, value))

    if removed:
        changes.append(Change('trackers', f"Removed {len(removed)} tracker{'s' if len(removed) > 1 else ''}"))

    # 3. Embed conversion
    converted_platform = None
    new_host = full_host_l
    new_path = parts.path
    for name, hosts, convert in EMBED_CONVERTERS:
        if full_host_l in hosts:
            before = new_host
            new_host, new_path = convert(full_host_l, parts.path)
            if new_host != before:
                changes.append(Change('embed', f'Converted to embed-friendly domain ({new_host})'))
                converted_platform = name
            break

    # 4. Platform label
    platform_label = converted_platform or detect_platform(hostname) or 'General'

    # 5. Rebuild URL
    new_query = '&'.join(f'{quote(k, safe="")}={quote(v, safe="")}' for k, v in kept_pairs)
    cleaned = urlunsplit((parts.scheme, new_host, new_path, new_query, ''))
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

_PRIVATE_NETS = True  # marker; real check done via ipaddress below

_TITLE_RE = re.compile(rb'<title[^>]*>([^<]*)</title>', re.I)

_USER_AGENT = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
)


def _is_blocked_host(hostname: str) -> bool:
    if not hostname:
        return True
    h = hostname.lower()
    if h == 'localhost' or h.endswith('.localhost'):
        return True
    try:
        ip = ipaddress.ip_address(h)
        return ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast
    except ValueError:
        pass
    # Resolve the hostname and reject if it lands on a non-public address
    # (covers 127/8, RFC1918 ranges, link-local incl. the 169.254.169.254
    # cloud metadata endpoint, etc.) so the bot can't be used to probe the
    # VPS's internal network via a crafted /fix link.
    try:
        infos = socket.getaddrinfo(h, None)
    except socket.gaierror:
        return False
    for info in infos:
        addr = info[4][0]
        try:
            ip = ipaddress.ip_address(addr)
        except ValueError:
            continue
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved or ip.is_multicast:
            return True
    return False


async def resolve_url(session: aiohttp.ClientSession, url: str) -> dict:
    """Follows redirects and extracts a page title, mirroring main-site/api/resolve.js."""
    parts = urlsplit(url)
    if parts.scheme not in ('http', 'https') or _is_blocked_host(parts.hostname or ''):
        return {'final_url': None, 'title': None}

    hostname = (parts.hostname or '').lower()
    is_youtube = hostname == 'youtube.com' or hostname.endswith('.youtube.com') or hostname == 'youtu.be'

    timeout = aiohttp.ClientTimeout(total=10)
    headers = {
        'User-Agent': _USER_AGENT,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
    }

    try:
        async with session.get(url, headers=headers, timeout=timeout, allow_redirects=True, max_redirects=10) as resp:
            final_url = str(resp.url)
            title = None

            if is_youtube:
                final_host = (urlsplit(final_url).hostname or '').lower().removeprefix('www.')
                if final_host != 'youtube.com' and 'youtu.be' not in final_url:
                    final_url = url
                try:
                    oembed = f'https://www.youtube.com/oembed?url={final_url}&format=json'
                    async with session.get(oembed, timeout=aiohttp.ClientTimeout(total=8)) as oe:
                        if oe.ok:
                            data = await oe.json(content_type=None)
                            title = data.get('title')
                except Exception:
                    pass
            else:
                content_type = resp.headers.get('content-type', '')
                if 'text/html' in content_type:
                    body = await resp.content.read(20000)
                    m = _TITLE_RE.search(body)
                    if m:
                        title = m.group(1).decode('utf-8', 'ignore').strip() or None

            return {'final_url': final_url, 'title': title}
    except Exception:
        return {'final_url': None, 'title': None}

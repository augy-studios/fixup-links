/* uwuFix - client-side URL cleaner & embed fixer */
'use strict';

// ===== CONSTANTS =====
const HISTORY_KEY = 'uwufix_history';
const MAXIMUM_HISTORY_ENTRIES = 100;

// ===== TRACKING PARAMETERS =====
// Any parameter whose name starts with one of these prefixes is a tracker,
// on every host. Catches the long tail of UTM variants (utm_creative,
// utm_pubreferrer, utm_swu, utm_brand, ...) that an exact-name list misses,
// plus Branch.io's attribution blobs (_branch_match_id, _branch_referrer, ...)
// which apps bolt onto otherwise clean deep links.
const TRACKER_PREFIXES = ['utm_', '_branch_'];

// Universal trackers removed from any URL. Keys are compared lowercased,
// so every entry here must be lowercase.
const UNIVERSAL_TRACKERS = new Set([
    // UTM (the utm_ prefix rule above covers the rest)
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    'utm_id', 'utm_reader', 'utm_name', 'utm_social', 'utm_social-type',
    // Click IDs
    'fbclid', 'gclid', 'gclsrc', 'msclkid', 'dclid', 'yclid', 'twclid', 'mc_eid',
    'igshid', 'igsh', 'igsi', 'li_fat_id', 'ttclid', 'sccid', 's_cid', 'snkrhsp',
    // Google Ads auto-tagging
    'gad_source', 'gad_campaignid',
    // General
    'ref', 'ref_src', 'ref_url', 'referral', 'source', 'srsltid',
    'icid', 'cid', 'eid', 'pid', 'sid', 'rid', 'uid', 'vid',
    '_ga', '_gl', '_hsenc', '_hsmi', 'hsa_acc', 'hsa_ad', 'hsa_cam', 'hsa_grp',
    'hsa_kw', 'hsa_mt', 'hsa_net', 'hsa_src', 'hsa_tgt', 'hsa_ver',
    'mibextid', 'mbid', 'ml_subscriber', 'ml_subscriber_hash',
    'wt.mc_id', 'wt.srch', 'affiliate', 'aff_id', 'aff_sub',
    'trk', 'track', 'tracking', 'trksid', 'tracesourcecode',
    // AMP page selector. Not tracking - it picks Google's stripped-down mobile
    // rendering - but the canonical page is what should be shared, and AMP is
    // deprecated. Dropping it redirects to the real article.
    'amp',
    // Google app share tag, e.g. shem=...,sh/x/discover/m1/4 on links shared
    // from Discover. The app adds it to whatever page was shared, not just
    // Google's own.
    'shem',
    // Klaviyo
    '_kx', 'kx', 'tw_source',
    // Triple Whale ad attribution (Shopify stores)
    'tw_adid', 'tw_campaign', 'tw_kwdid',
    // Branch.io attribution keys that don't carry the _branch_ prefix. The
    // routing params ($deeplink_path, $fallback_url, $ios_url, ...) are left
    // alone - those decide where the link actually goes.
    '~channel', '~feature', '~campaign', '~tags', '~stage', '~creation_source',
    '~click_id', '~referring_link', '~id', '~secondary_publisher',
    '$3p', '$original_url', '$identity_id', '$s2s',
]);

// Platform-specific parameter sets. Keys are compared lowercased, so every
// entry here must be lowercase.
const PLATFORM_TRACKERS = {
    'twitter.com': new Set([
        's', 't', 'a', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
        'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url',
    ]),
    'x.com': new Set([
        's', 't', 'a', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
        'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url',
    ]),
    'instagram.com': new Set([
        'igshid', 'igsh', 'igsi', 'ig_rid', 'ig_mid', 'stp', 'smid', 'hl',
        'taken-by',
    ]),
    'facebook.com': new Set([
        '__cft__', '__tn__', '__xts__', 'hc_ref', 'fref', 'rc',
        'theater', 'refsrc', 'source', '_rdr',
        'referral_source', 'surface_type', 'in_reels_tab_context',
    ]),
    'fb.com': new Set([
        '__cft__', '__tn__', '__xts__', 'hc_ref', 'fref', 'rc',
        'theater', 'refsrc', 'source', '_rdr',
        'referral_source', 'surface_type', 'in_reels_tab_context',
    ]),
    'youtube.com': new Set([
        'feature', 'app', 'list', 'index', 'pp', 'si', 'is', 'ab_channel',
        'cbrd', 'ucbcb', 'pbc', 'pbj',
    ]),
    'youtu.be': new Set(['feature', 'si', 'is']),
    'tiktok.com': new Set([
        '_d', 'checksum', 'is_copy_url', 'is_from_webapp',
        'sender_device', 'sender_web_id', 'share_app_id', 'share_link_id',
        'tt_from', 'tt_medium', 'tt_campaign', 'tiktok_share_from',
        'source_ref', 'sec_uid', '_r',
    ]),
    'reddit.com': new Set([
        'utm_name', 'ref_source', 'ref', 'context', 'share_id',
        'post_fullname', 'cid', 'subreddit_id', 'post_index',
    ]),
    'linkedin.com': new Set([
        'trk', 'trkinfo', 'trk_sid', 'originalsubdomain', 'refid',
        'lipi', 'licu', 'lici', 'sharer', 'trackingid', 'rcm',
    ]),
    'amazon.com': new Set([
        'ref', 'ref_', 'pf_rd_r', 'pf_rd_p', 'pf_rd_i', 'pf_rd_m', 'pf_rd_s', 'pf_rd_t',
        'pd_rd_r', 'pd_rd_w', 'pd_rd_wg', '_encoding', 'smid', 'sprefix', 'sr',
        'ie', 'qid', 'rps', 'linkcode', 'linkid', 'ascsubtag', 'tag',
        'creative', 'creativeasin',
    ]),
    'google.com': new Set([
        'ved', 'usg', 'ei', 'sei', 'sa', 'sqi', 'sourceid',
        'client', 'channel', 'rlz', 'oq',
    ]),
    'substack.com': new Set([
        'r', 'utm_source', 'utm_medium', 'utm_campaign', 'publication_id', 'post_id',
    ]),
    'github.com': new Set([
        'ref', 'notification_referrer_id', 'bpo',
    ]),
    'discord.com': new Set(['ref', 'source']),
    'pinterest.com': new Set(['sent_episod', 'nic']),
    'snapchat.com': new Set(['sc_referrer', 'share_id']),
    'ebay.com': new Set([
        'mkevt', 'mkcid', 'mkrid', 'campid', 'toolid', 'customid',
        'epid', 'hash', '_trkparms', '_trksid',
    ]),
    'aliexpress.com': new Set([
        'aff_platform', 'aff_trace_key', 'terminal_id', 'biztype', 'sourcetype',
        'btsid', 'ws_ab_test', 'initiative_id', 'origin_design_token',
    ]),
    'spotify.com': new Set([
        'si', 'context', 'nd',
    ]),
    'threads.net': new Set([
        'igshid', 'igsh', 'igsi', 'mibextid', 'xmt', 'slof',
    ]),
    'threads.com': new Set([
        'igshid', 'igsh', 'igsi', 'mibextid', 'xmt', 'slof',
    ]),
    'twitch.tv': new Set([
        'tt_content', 'tt_medium', 'sr', 'filter', 'referrer',
    ]),
    'pixiv.net': new Set([
        'lang',
    ]),
    'tumblr.com': new Set([
        'is_related_post', 'source',
    ]),
    'bilibili.com': new Set([
        'spm_id_from', 'vd_source', 'from_source', 'share_source',
        'share_medium', 'share_plat', 'share_session_id', 'share_tag',
        'timestamp', 'unique_k', 'bbid', 'ts',
    ]),
    'bsky.app': new Set([
        'ref_src', 'ref_url',
    ]),
    // Eightfold career sites (<tenant>.eightfold.ai/careers/job/<id>) tack on
    // the tenant's own domain and a UI locale; the subdomain already picks the
    // tenant and the posting lives at its path.
    'eightfold.ai': new Set([
        'domain', 'hl',
    ]),
    // Samsung Community (Khoros forums on regional subdomains such as
    // r1.community.samsung.com) tags shared posts with src=ShareByUserCM.
    // Scoped to the forums: src is too generic a name to strip everywhere.
    'community.samsung.com': new Set([
        'src',
    ]),
};

// Platform trackers matched by shape instead of by name, for keys a platform
// rotates faster than a list can keep up. Tested against the lowercased key.
// Every host here must also be a PLATFORM_TRACKERS key, which picks the platform.
const PLATFORM_TRACKER_PATTERNS = {
    // Instagram share links carry a random four-letter key (stkn, psln, dlrf,
    // ...) that changes every few weeks. ?next= on the login page is the only
    // four-letter parameter an Instagram link needs.
    'instagram.com': /^(?!next$)[a-z]{4}$/,
};

// ===== FULL QUERY-STRIP HOSTS =====
// Workday job postings (<tenant>.wdN.myworkdayjobs.com/<locale>/<site>/job/...,
// plus the myworkdaysite.com variant) carry whatever search facets the sharer
// happened to have selected - timeType, locationCountry, and jobFamilyGroup
// repeated once per checked box - and the facet names are defined per tenant,
// so no fixed list keeps up with them. The posting is addressed entirely by its
// path, so the whole query string goes. Only /job/ pages qualify: on the search
// listing above them those same params ARE the search.
const STRIP_ALL_PARAMETER_HOSTS = ['myworkdayjobs.com', 'myworkdaysite.com'];
const STRIP_ALL_PARAMETER_PATH = '/job/';

function stripsAllParameters(hostname, pathname) {
    const isStripAllHost = STRIP_ALL_PARAMETER_HOSTS.some(function (stripHost) {
        return hostname === stripHost || hostname.endsWith('.' + stripHost);
    });
    return isStripAllHost && pathname.includes(STRIP_ALL_PARAMETER_PATH);
}

// Mastodon has no single hostname, so instances have to be enumerated. This is
// the set FxMastodon covers.
const MASTODON_INSTANCES = [
    'mastodon.social', 'mstdn.jp', 'mastodon.cloud', 'mstdn.social',
    'mastodon.world', 'mastodon.online', 'mas.to', 'techhub.social',
    'mastodon.uno', 'infosec.exchange',
];

// ===== EMBED CONVERSION RULES =====
// Each converter has a name (the platform label), a match function that is
// given the original hostname, and a convert function that rewrites the URL.
const EMBED_CONVERTERS = [{
        name: 'X / Twitter',
        match: function (hostname) {
            return hostname === 'x.com' || hostname === 'twitter.com' || hostname === 'www.x.com' || hostname === 'www.twitter.com';
        },
        convert: function (url) {
            url.hostname = 'fixupx.com';
            const statusMatch = url.pathname.match(/^\/[^/]+\/(status\/\d+)$/);
            if (statusMatch) {
                url.pathname = '/i/' + statusMatch[1];
            }
            return url;
        },
    },
    {
        name: 'Instagram',
        match: function (hostname) {
            return hostname === 'instagram.com' || hostname === 'www.instagram.com';
        },
        convert: function (url) {
            url.hostname = 'www.oginstagram.com';
            return url;
        },
    },
    {
        name: 'YouTube',
        match: function (hostname) {
            return hostname === 'youtube.com' || hostname === 'www.youtube.com' || hostname === 'm.youtube.com';
        },
        convert: function (url) {
            // Only Shorts need an embed fix - regular watch links already
            // preview fine, so leave them on youtube.com.
            if (/^\/shorts\//.test(url.pathname)) {
                url.hostname = 'koutube.com';
            }
            return url;
        },
    },
    {
        name: 'TikTok',
        match: function (hostname) {
            return hostname === 'tiktok.com' || hostname === 'www.tiktok.com' || hostname === 'vm.tiktok.com' || hostname === 'vt.tiktok.com';
        },
        convert: function (url) {
            // Preserve the subdomain so vm./vt. share links keep resolving on
            // the matching tnktok.com subdomain.
            const withoutWww = url.hostname.replace(/^www\./, '');
            url.hostname = withoutWww.replace(/tiktok\.com$/, 'tnktok.com');
            return url;
        },
    },
    {
        name: 'Facebook',
        match: function (hostname) {
            return hostname === 'facebook.com' || hostname === 'www.facebook.com' || hostname === 'fb.com' || hostname === 'www.fb.com' || hostname === 'm.facebook.com';
        },
        convert: function (url) {
            url.hostname = 'www.facebed.com';
            return url;
        },
    },
    {
        name: 'Reddit',
        match: function (hostname) {
            return hostname === 'reddit.com' || hostname === 'www.reddit.com' || hostname === 'old.reddit.com' || hostname === 'new.reddit.com';
        },
        convert: function (url) {
            url.hostname = 'www.vxreddit.com';
            return url;
        },
    },
    {
        name: 'Discord',
        match: function (hostname) {
            return hostname === 'canary.discord.com' || hostname === 'ptb.discord.com';
        },
        convert: function (url) {
            url.hostname = 'discord.com';
            return url;
        },
    },
    {
        name: 'Threads',
        match: function (hostname) {
            return hostname === 'threads.net' || hostname === 'www.threads.net' || hostname === 'threads.com' || hostname === 'www.threads.com';
        },
        convert: function (url) {
            url.hostname = 'fixthreads.seria.moe';
            return url;
        },
    },
    {
        name: 'Bluesky',
        match: function (hostname) {
            return hostname === 'bsky.app' || hostname === 'www.bsky.app';
        },
        convert: function (url) {
            url.hostname = 'fxbsky.app';
            return url;
        },
    },
    {
        name: 'Twitch',
        match: function (hostname) {
            return hostname === 'twitch.tv' || hostname === 'www.twitch.tv' || hostname === 'm.twitch.tv';
        },
        convert: function (url) {
            url.hostname = 'fxtwitch.seria.moe';
            return url;
        },
    },
    {
        // Album and prerelease pages render fine on their own, so leave those
        // on spotify.com.
        name: 'Spotify',
        match: function (hostname) {
            return hostname === 'open.spotify.com' || hostname === 'spotify.com' || hostname === 'www.spotify.com';
        },
        convert: function (url) {
            if (!/^(\/intl-[^/]+)?\/(album|prerelease)\//.test(url.pathname)) {
                url.hostname = 'fxspotify.com';
            }
            return url;
        },
    },
    {
        name: 'Pixiv',
        match: function (hostname) {
            return hostname === 'pixiv.net' || hostname === 'www.pixiv.net';
        },
        convert: function (url) {
            url.hostname = 'phixiv.net';
            return url;
        },
    },
    {
        name: 'Tumblr',
        match: function (hostname) {
            return hostname === 'tumblr.com' || hostname === 'www.tumblr.com';
        },
        convert: function (url) {
            url.hostname = 'tpmblr.com';
            return url;
        },
    },
    {
        name: 'BiliBili',
        match: function (hostname) {
            return hostname === 'bilibili.com' || hostname === 'www.bilibili.com' || hostname === 'm.bilibili.com';
        },
        convert: function (url) {
            url.hostname = 'vxbilibili.com';
            return url;
        },
    },
    {
        // fixDeviantArt only handles deviation and journal pages; a profile or
        // gallery link would 404 there, so leave those on deviantart.com.
        name: 'DeviantArt',
        match: function (hostname) {
            return hostname === 'deviantart.com' || hostname === 'www.deviantart.com';
        },
        convert: function (url) {
            if (/^\/[^/]+\/(art|journal)\/[^/]+/.test(url.pathname)) {
                url.hostname = 'fixdeviantart.com';
            }
            return url;
        },
    },
    {
        // FixNewgrounds covers art pages only.
        name: 'Newgrounds',
        match: function (hostname) {
            return hostname === 'newgrounds.com' || hostname === 'www.newgrounds.com';
        },
        convert: function (url) {
            if (/^\/art\/view\/[^/]+\/[^/]+/.test(url.pathname)) {
                url.hostname = 'fixnewgrounds.com';
            }
            return url;
        },
    },
    {
        // xfuraffinity covers submission pages only.
        name: 'Fur Affinity',
        match: function (hostname) {
            return hostname === 'furaffinity.net' || hostname === 'www.furaffinity.net';
        },
        convert: function (url) {
            if (/^\/view\/[^/]+/.test(url.pathname)) {
                url.hostname = 'xfuraffinity.net';
            }
            return url;
        },
    },
    {
        // FxMastodon isn't a plain host swap - the instance becomes the first
        // path segment: fx.zillanlabs.tech/mastodon.social/@user/12345
        name: 'Mastodon',
        match: function (hostname) {
            return MASTODON_INSTANCES.includes(hostname.replace(/^www\./, ''));
        },
        convert: function (url) {
            if (/^\/@[^/]+\/[^/]+/.test(url.pathname)) {
                url.pathname = '/' + url.hostname.replace(/^www\./, '') + url.pathname;
                url.hostname = 'fx.zillanlabs.tech';
            }
            return url;
        },
    },
];

// ===== TRACKER MATCHING =====
// Matching is always case-insensitive: query keys arrive in whatever case the
// sharing app produced (?UTM_Source=..., ?FBCLID=...), and those are the same
// tracker.
function isTrackerParameter(key, platformSet, platformPattern) {
    const lowercaseKey = key.toLowerCase();
    const hasTrackerPrefix = TRACKER_PREFIXES.some(function (prefix) {
        return lowercaseKey.startsWith(prefix);
    });
    if (hasTrackerPrefix) {
        return true;
    }
    if (UNIVERSAL_TRACKERS.has(lowercaseKey)) {
        return true;
    }
    if (platformPattern && platformPattern.test(lowercaseKey)) {
        return true;
    }
    return Boolean(platformSet && platformSet.has(lowercaseKey));
}

// ===== GOOGLE SEARCH DESTINATION EXTRACTION =====
function extractGoogleDestination(url) {
    let query = url.searchParams.get('url');
    if (!query) {
        query = url.searchParams.get('q');
    }
    if (!query) {
        return null;
    }
    try {
        const destination = new URL(query);
        return destination.toString();
    } catch {
        return null;
    }
}

// ===== CORE CLEANER =====
/**
 * Cleans one link: normalizes YouTube hosts, pulls the destination out of a
 * Google Search redirect, removes tracking parameters, and swaps the host for
 * an embed-friendly one where a fixer exists.
 * Returns { cleaned, changes, platform, wasConverted }, where changes is the
 * list of tags shown under the result. Throws an Error with a message for the
 * person when the input isn't a usable http(s) link.
 */
function cleanUrl(rawInput) {
    const input = rawInput.trim();
    if (!input) {
        throw new Error('Please enter a URL.');
    }

    let url;
    try {
        let fullInput = input;
        if (!input.startsWith('http')) {
            fullInput = 'https://' + input;
        }
        url = new URL(fullInput);
    } catch {
        throw new Error('That doesn\'t look like a valid URL. Please include https://');
    }

    if (!['http:', 'https:'].includes(url.protocol)) {
        throw new Error('Only http:// and https:// URLs are supported.');
    }

    let hostname = url.hostname.replace(/^www\./, '');
    const changes = [];

    // 0. Normalize youtu.be -> youtube.com for consistency
    if (hostname === 'youtu.be') {
        const videoId = url.pathname.replace(/^\/|\/$/g, '');
        if (videoId) {
            url.hostname = 'www.youtube.com';
            url.pathname = '/watch';
            url.searchParams.set('v', videoId);
            hostname = 'youtube.com';
            changes.push({ type: 'embed', label: 'Converted youtu.be to youtube.com' });
        }
    }

    // 0b. Normalize the mobile YouTube host so links open the full site
    if (url.hostname.toLowerCase() === 'm.youtube.com') {
        url.hostname = 'www.youtube.com';
        hostname = 'youtube.com';
        changes.push({ type: 'embed', label: 'Converted m.youtube.com to www.youtube.com' });
    }

    // 1. Google Search - extract destination
    if (hostname === 'google.com' || hostname.endsWith('.google.com')) {
        const destination = extractGoogleDestination(url);
        if (destination) {
            changes.push({
                type: 'redirect',
                label: 'Extracted destination from Google Search'
            });
            return {
                cleaned: destination,
                changes,
                platform: 'Google Search',
                wasConverted: false
            };
        }
    }

    // 2. Remove platform-specific trackers
    const platformKey = Object.keys(PLATFORM_TRACKERS).find(function (platformHost) {
        return hostname === platformHost || hostname.endsWith('.' + platformHost);
    });

    let platformSet = null;
    let platformPattern = null;
    if (platformKey) {
        platformSet = PLATFORM_TRACKERS[platformKey];
        platformPattern = PLATFORM_TRACKER_PATTERNS[platformKey];
    }
    const stripAll = stripsAllParameters(hostname, url.pathname);
    const removedParameters = [];

    const keysToDelete = [];
    for (const [key] of url.searchParams) {
        if (stripAll || isTrackerParameter(key, platformSet, platformPattern)) {
            keysToDelete.push(key);
            removedParameters.push(key);
        }
    }
    for (const key of keysToDelete) {
        url.searchParams.delete(key);
    }

    if (removedParameters.length > 0) {
        let trackerWord = 'tracker';
        if (removedParameters.length > 1) {
            trackerWord = 'trackers';
        }
        changes.push({
            type: 'trackers',
            label: `Removed ${removedParameters.length} ${trackerWord}`,
            params: removedParameters,
        });
    }

    // 3. Embed conversion
    let convertedPlatform = null;
    let wasConverted = false;

    for (const converter of EMBED_CONVERTERS) {
        if (converter.match(url.hostname)) {
            const hostnameBefore = url.hostname;
            const result = converter.convert(url);
            if (result.hostname !== hostnameBefore) {
                changes.push({
                    type: 'embed',
                    label: `Converted to embed-friendly domain (${url.hostname})`
                });
                convertedPlatform = converter.name;
                wasConverted = true;
            }
            break;
        }
    }

    // 4. Detect platform label for history
    let platformLabel = convertedPlatform;
    if (!platformLabel) {
        platformLabel = detectPlatform(hostname);
    }
    if (!platformLabel) {
        platformLabel = 'General';
    }

    // 5. Clean up empty query string
    let cleaned = url.toString();
    if (cleaned.endsWith('?')) {
        cleaned = cleaned.slice(0, -1);
    }

    if (changes.length === 0) {
        changes.push({
            type: 'clean',
            label: 'URL was already clean'
        });
    }

    return {
        cleaned,
        changes,
        platform: platformLabel,
        wasConverted
    };
}

/**
 * The platform name shown in history for a hostname (www. already removed),
 * or null when it isn't a known platform.
 */
function detectPlatform(hostname) {
    const platformNames = {
        'twitter.com': 'X / Twitter',
        'x.com': 'X / Twitter',
        'instagram.com': 'Instagram',
        'tiktok.com': 'TikTok',
        'reddit.com': 'Reddit',
        'youtube.com': 'YouTube',
        'youtu.be': 'YouTube',
        'facebook.com': 'Facebook',
        'fb.com': 'Facebook',
        'linkedin.com': 'LinkedIn',
        'amazon.com': 'Amazon',
        'substack.com': 'Substack',
        'github.com': 'GitHub',
        'discord.com': 'Discord',
        'pinterest.com': 'Pinterest',
        'snapchat.com': 'Snapchat',
        'spotify.com': 'Spotify',
        'ebay.com': 'eBay',
        'aliexpress.com': 'AliExpress',
        'threads.net': 'Threads',
        'threads.com': 'Threads',
        'bsky.app': 'Bluesky',
        'twitch.tv': 'Twitch',
        'pixiv.net': 'Pixiv',
        'tumblr.com': 'Tumblr',
        'bilibili.com': 'BiliBili',
        'deviantart.com': 'DeviantArt',
        'newgrounds.com': 'Newgrounds',
        'furaffinity.net': 'Fur Affinity',
        'google.com': 'Google',
        'myworkdayjobs.com': 'Workday',
        'myworkdaysite.com': 'Workday',
        'eightfold.ai': 'Eightfold',
        'community.samsung.com': 'Samsung Community',
    };
    for (const [platformHost, platformName] of Object.entries(platformNames)) {
        if (hostname === platformHost || hostname.endsWith('.' + platformHost)) {
            return platformName;
        }
    }
    if (MASTODON_INSTANCES.includes(hostname)) {
        return 'Mastodon';
    }
    return null;
}

// ===== HISTORY =====
function loadHistory() {
    try {
        let storedHistory = localStorage.getItem(HISTORY_KEY);
        if (!storedHistory) {
            storedHistory = '[]';
        }
        return JSON.parse(storedHistory);
    } catch {
        return [];
    }
}

// Every change is told to whoever shows the history (js/sync.js shares it with another device).
function saveHistory(items) {
    localStorage.setItem(HISTORY_KEY, JSON.stringify(items));
    document.dispatchEvent(new CustomEvent('uwufix:history'));
}

function addToHistory(original, cleaned, platform, title = null) {
    let history = loadHistory();
    // Remove duplicate of same cleaned URL
    history = history.filter(function (historyEntry) {
        return historyEntry.cleaned !== cleaned;
    });
    const entry = {
        id: Date.now(),
        original,
        cleaned,
        platform,
        title,
        date: new Date().toISOString(),
    };
    history.unshift(entry);
    if (history.length > MAXIMUM_HISTORY_ENTRIES) {
        history = history.slice(0, MAXIMUM_HISTORY_ENTRIES);
    }
    saveHistory(history);
    return entry;
}

function removeFromHistory(id) {
    let history = loadHistory();
    history = history.filter(function (historyEntry) {
        return historyEntry.id !== id;
    });
    saveHistory(history);
    return history;
}

function clearHistory() {
    localStorage.removeItem(HISTORY_KEY);
    document.dispatchEvent(new CustomEvent('uwufix:history'));
}

function updateHistoryEntry(id, updates) {
    const history = loadHistory();
    const entry = history.find(function (historyEntry) {
        return historyEntry.id === id;
    });
    if (entry) {
        Object.assign(entry, updates);
        saveHistory(history);
    }
}

// "just now", "5m ago", "3h ago", "2d ago", or the date itself after a week.
function formatRelativeDate(isoDate) {
    const now = Date.now();
    const then = new Date(isoDate).getTime();
    const difference = now - then;
    const minutes = Math.floor(difference / 60000);
    if (minutes < 1) {
        return 'just now';
    }
    if (minutes < 60) {
        return `${minutes}m ago`;
    }
    const hours = Math.floor(minutes / 60);
    if (hours < 24) {
        return `${hours}h ago`;
    }
    const days = Math.floor(hours / 24);
    if (days < 7) {
        return `${days}d ago`;
    }
    return new Date(isoDate).toLocaleDateString();
}

// ===== TOAST =====
let toastTimer;

function showToast(message) {
    const toast = document.getElementById('toast');
    toast.textContent = message;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () {
        toast.classList.remove('show');
    }, 2200);
}

// ===== MODALS =====
// openModal / closeModal come from js/ui.js

// ===== UI RENDERING =====
/** Draws one tag per change under the result, each with an icon for its type. */
function renderChangeTags(changes) {
    const container = document.getElementById('changesSummary');
    container.innerHTML = '';
    for (const change of changes) {
        const tag = document.createElement('span');
        tag.className = 'change-tag';

        let svgHtml = '';
        if (change.type === 'trackers') {
            svgHtml = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/></svg>`;
        } else if (change.type === 'embed') {
            svgHtml = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>`;
        } else if (change.type === 'redirect') {
            svgHtml = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5l7 7-7 7"/></svg>`;
        } else {
            svgHtml = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`;
        }

        tag.innerHTML = svgHtml + change.label;
        container.appendChild(tag);
    }
}

/**
 * Redraws the History window from storage: the count badge, the empty state,
 * and one row per entry. Clicking a row loads its original link into the
 * input; its bin button deletes it.
 */
function renderHistoryList() {
    const history = loadHistory();
    const list = document.getElementById('historyList');
    const badge = document.getElementById('historyCountBadge');

    badge.textContent = history.length;

    // Remove only history items, preserve the empty-state element
    const oldItems = list.querySelectorAll('.history-item');
    for (const oldItem of oldItems) {
        oldItem.remove();
    }

    const emptyState = document.getElementById('historyEmpty');
    if (history.length === 0) {
        if (emptyState) {
            emptyState.hidden = false;
        }
        return;
    }

    if (emptyState) {
        emptyState.hidden = true;
    }

    for (const entry of history) {
        const item = document.createElement('div');
        item.className = 'history-item';
        item.setAttribute('role', 'button');
        item.setAttribute('tabindex', '0');
        item.setAttribute('aria-label', `Load: ${entry.cleaned}`);

        let titleHtml = '';
        if (entry.title) {
            titleHtml = `<div class="history-item-title">${escapeHtml(entry.title)}</div>`;
        }

        item.innerHTML = `
      <div class="history-item-content">
        ${titleHtml}
        <div class="history-item-original-label">Original</div>
        <div class="history-item-original">${escapeHtml(entry.original)}</div>
        <div class="history-item-cleaned">${escapeHtml(entry.cleaned)}</div>
        <div class="history-item-meta">
          <span class="history-item-date">${formatRelativeDate(entry.date)}</span>
          <span class="history-item-platform">${escapeHtml(entry.platform)}</span>
        </div>
      </div>
      <button class="history-item-delete" aria-label="Delete entry">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="3 6 5 6 21 6"/>
          <path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/>
          <path d="M10 11v6M14 11v6"/>
          <path d="M9 6V4a1 1 0 011-1h4a1 1 0 011 1v2"/>
        </svg>
      </button>
    `;

        item.querySelector('.history-item-content').addEventListener('click', function () {
            document.getElementById('urlInput').value = entry.original;
            closeModal('historyModal');
            document.getElementById('urlInput').focus();
            showToast('URL loaded from history');
        });

        item.querySelector('.history-item-delete').addEventListener('click', function (event) {
            event.stopPropagation();
            removeFromHistory(entry.id);
            renderHistoryList();
            showToast('Entry deleted');
        });

        item.addEventListener('keydown', function (event) {
            if (event.key === 'Enter' || event.key === ' ') {
                item.querySelector('.history-item-content').click();
            }
        });

        list.appendChild(item);
    }
}

function escapeHtml(text) {
    return text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

// ===== METADATA & REDIRECT =====
function extractUrlFromText(text) {
    if (!text) {
        return null;
    }
    const match = text.match(/https?:\/\/\S+/);
    if (match) {
        return match[0];
    }
    // A link with no https:// in front, such as x.com/user/status/1 highlighted in a chat and
    // sent from the Android app's "Fix link": one word with a dot in it. cleanUrl adds https://.
    const bareText = text.trim();
    if (/^[^\s/]+\.[a-z]{2,}(\/\S*)?$/i.test(bareText)) {
        return bareText;
    }
    return null;
}

// The text with its link swapped for the fixed one, for the Android app's Replace: a link
// highlighted inside a sentence keeps the sentence around it.
function replaceLinkInText(text, link, fixed) {
    let linkPosition = -1;
    if (link) {
        linkPosition = text.indexOf(link);
    }
    if (linkPosition === -1) {
        return fixed;
    }
    return text.slice(0, linkPosition) + fixed + text.slice(linkPosition + link.length);
}

// Whether following a link ended up on a different site (www. ignored).
function isMeaningfulRedirect(fromUrl, toUrl) {
    try {
        const from = new URL(fromUrl);
        const to = new URL(toUrl);
        function normalizeHost(host) {
            return host.toLowerCase().replace(/^www\./, '');
        }
        return normalizeHost(from.hostname) !== normalizeHost(to.hostname);
    } catch {
        return false;
    }
}

// Whether two links are the same page: same host (www. ignored) and path (trailing / ignored).
function urlsEquivalent(firstUrl, secondUrl) {
    try {
        const firstParsed = new URL(firstUrl);
        const secondParsed = new URL(secondUrl);
        function normalize(parsedUrl) {
            return parsedUrl.hostname.toLowerCase().replace(/^www\./, '') + parsedUrl.pathname.replace(/\/$/, '');
        }
        return normalize(firstParsed) === normalize(secondParsed);
    } catch {
        return false;
    }
}

// Asks /api/resolve where a link ends up and what its page is called.
// Resolves to { title, finalUrl } (either may be null), or null on any failure.
async function fetchMetadata(url) {
    try {
        const response = await fetch(`/api/resolve?url=${encodeURIComponent(url)}`, {
            signal: AbortSignal.timeout(12000),
        });
        if (!response.ok) {
            return null;
        }
        const json = await response.json();
        if (!json.finalUrl && !json.title) {
            return null;
        }
        let title = null;
        if (json.title) {
            title = json.title;
        }
        let finalUrl = null;
        if (json.finalUrl) {
            finalUrl = json.finalUrl;
        }
        return {
            title: title,
            finalUrl: finalUrl,
        };
    } catch {
        return null;
    }
}

// ===== MAIN PROCESS =====
/**
 * Runs when Clean is pressed: cleans the link in the input, shows the result
 * and its change tags, and saves it to history. Then, when online, looks the
 * link up in the background to follow redirects and fetch the page title,
 * updating the result and the history entry when the answer arrives.
 */
async function processUrl() {
    const input = document.getElementById('urlInput').value.trim();
    const resultArea = document.getElementById('resultArea');
    const errorArea = document.getElementById('errorArea');
    const resultUrl = document.getElementById('resultUrl');
    const errorMessage = document.getElementById('errorMsg');

    resultArea.hidden = true;
    errorArea.hidden = true;

    if (!input) {
        errorMessage.textContent = 'Please enter a URL first.';
        errorArea.hidden = false;
        return;
    }

    let cleanResult;
    try {
        cleanResult = cleanUrl(input);
    } catch (error) {
        errorMessage.textContent = error.message;
        errorArea.hidden = false;
        return;
    }

    const cleaned = cleanResult.cleaned;
    const changes = cleanResult.changes;
    const platform = cleanResult.platform;

    resultUrl.textContent = cleaned;
    renderChangeTags(changes);
    resultArea.hidden = false;
    window._uwufixLastCleaned = cleaned;

    const historyEntry = addToHistory(input, cleaned, platform);
    renderHistoryList();

    // Async: fetch page title + detect redirects (requires network)
    if (!navigator.onLine) {
        showToast('You\'re offline - redirect detection & title lookup skipped');
        return;
    }

    fetchMetadata(cleaned).then(function (metadata) {
        if (!metadata) {
            return;
        }
        const updates = {};

        if (metadata.title) {
            updates.title = metadata.title;
        }

        if (metadata.finalUrl && isMeaningfulRedirect(cleaned, metadata.finalUrl) && !urlsEquivalent(metadata.finalUrl, input)) {
            let finalCleaned = metadata.finalUrl;
            try {
                finalCleaned = cleanUrl(metadata.finalUrl).cleaned;
            } catch {
                // Not cleanable: show the final link as it came.
            }

            document.getElementById('resultUrl').textContent = finalCleaned;
            window._uwufixLastCleaned = finalCleaned;
            const redirectHost = new URL(finalCleaned).hostname;
            renderChangeTags([...changes, { type: 'redirect', label: `Redirects to ${redirectHost}` }]);
            updates.cleaned = finalCleaned;

            // Title from the redirect response may be unreliable - fetch it directly
            // from the final destination, then update history once it arrives
            if (!updates.title) {
                fetchMetadata(finalCleaned).then(function (finalMetadata) {
                    if (finalMetadata?.title) {
                        updateHistoryEntry(historyEntry.id, { title: finalMetadata.title });
                        renderHistoryList();
                    }
                }).catch(function () {});
            }
        }

        if (Object.keys(updates).length) {
            updateHistoryEntry(historyEntry.id, updates);
            renderHistoryList();
        }
    }).catch(function () {});
}

// ===== CLIPBOARD =====
async function pasteFromClipboard() {
    try {
        // The Android app's WebView can't read the clipboard for a page, so the app does.
        let text;
        if (window.AppBridge?.native) {
            const answer = await AppBridge.call('Fixup', 'paste');
            text = answer.text;
        } else {
            text = await navigator.clipboard.readText();
        }
        if (text) {
            document.getElementById('urlInput').value = text.trim();
            showToast('Pasted from clipboard');
        }
    } catch {
        showToast('Clipboard access denied! Please paste manually.');
    }
}

async function copyToClipboard(text) {
    try {
        await navigator.clipboard.writeText(text);
        showToast('Copied to clipboard');
    } catch {
        // Fallback
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.opacity = '0';
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
        showToast('Copied to clipboard');
    }
}

// ===== SHARE =====
async function shareUrl(url) {
    if (navigator.share) {
        try {
            await navigator.share({
                url,
                title: 'Cleaned URL from uwuFix'
            });
        } catch {
            // User cancelled
        }
    } else {
        await copyToClipboard(url);
        showToast('Copied (Web Share not available)');
    }
}

// ===== INIT =====
/**
 * Wires up the page once its markup is ready: the history window, the Clean,
 * Paste, Clear, Copy, Open, Share and QR buttons, a link passed in the page
 * address (share target, or the Android app's quick screen), the app's Replace
 * button, and Escape to close any window.
 */
document.addEventListener('DOMContentLoaded', function () {
    // Theme init and modal wiring live in js/theme.js
    renderHistoryList();
    // History merged in from another device (js/sync.js), or changed here.
    document.addEventListener('uwufix:history', renderHistoryList);

    // ---- History modal ----
    document.getElementById('openHistoryModal').addEventListener('click', function () {
        renderHistoryList();
        openModal('historyModal');
    });
    document.getElementById('clearHistoryBtn').addEventListener('click', function () {
        if (confirm('Clear all history?')) {
            clearHistory();
            renderHistoryList();
            showToast('History cleared');
        }
    });

    // ---- Clean button ----
    document.getElementById('cleanBtn').addEventListener('click', processUrl);

    // Allow Enter in the input
    document.getElementById('urlInput').addEventListener('keydown', function (event) {
        if (event.key === 'Enter') {
            processUrl();
        }
    });

    // ---- Paste / Clear input ----
    document.getElementById('pasteBtn').addEventListener('click', pasteFromClipboard);
    document.getElementById('clearInputBtn').addEventListener('click', function () {
        document.getElementById('urlInput').value = '';
        document.getElementById('resultArea').hidden = true;
        document.getElementById('errorArea').hidden = true;
        window._uwufixLastCleaned = null;
        document.getElementById('urlInput').focus();
    });

    // ---- Result actions ----
    document.getElementById('copyBtn').addEventListener('click', function () {
        const url = window._uwufixLastCleaned;
        if (url) {
            copyToClipboard(url);
        }
    });

    document.getElementById('openBtn').addEventListener('click', function () {
        const url = window._uwufixLastCleaned;
        if (!url) {
            return;
        }
        // In the Android app, in whichever app opens it (the browser, or X for fixupx.com).
        if (window.AppBridge?.native) {
            AppBridge.call('Fixup', 'open', { url }).catch(function (error) {
                showToast(error.message);
            });
        } else {
            window.open(url, '_blank', 'noopener,noreferrer');
        }
    });

    document.getElementById('shareBtn').addEventListener('click', function () {
        const url = window._uwufixLastCleaned;
        if (url) {
            shareUrl(url);
        }
    });

    // ---- QR Code modal ----
    document.getElementById('qrBtn').addEventListener('click', function () {
        const url = window._uwufixLastCleaned;
        if (!url) {
            return;
        }
        const container = document.getElementById('qrContainer');
        container.innerHTML = '';
        new QRCode(container, {
            text: url,
            width: 240,
            height: 240,
            colorDark: '#000000',
            colorLight: '#ffffff',
            correctLevel: QRCode.CorrectLevel.M,
        });
        document.getElementById('qrUrl').textContent = url;
        openModal('qrModal');
    });

    // ---- Auto-paste if URL in query string (also handles share_target via ?link=) ----
    // The Android app's quick screen comes in this way too, with ?text= holding what was shared
    // or highlighted (FixActivity.java: the WebView app's, and flutter/android's).
    const queryParameters = new URLSearchParams(window.location.search);
    let sharedText = queryParameters.get('text');
    if (!sharedText) {
        sharedText = '';
    }
    let sharedUrl = queryParameters.get('url');
    if (!sharedUrl) {
        sharedUrl = queryParameters.get('link');
    }
    if (!sharedUrl) {
        sharedUrl = extractUrlFromText(sharedText);
    }
    if (sharedUrl) {
        document.getElementById('urlInput').value = sharedUrl;
        setTimeout(processUrl, 100);
    }

    // ---- The Android app's quick screen: Replace ----
    // Text highlighted in a box you can type in: the fixed link goes back in place of the one
    // highlighted, and the quick screen closes, back to that app.
    if (window.AppBridge?.native) {
        AppBridge.ready(5000).then(function () {
            if (!AppBridge.quick()?.replace || !sharedUrl) {
                return;
            }
            const replaceButton = document.getElementById('replaceBtn');
            replaceButton.hidden = false;
            replaceButton.addEventListener('click', function () {
                const fixed = window._uwufixLastCleaned;
                if (!fixed) {
                    return;
                }
                const replacedText = replaceLinkInText(sharedText, sharedUrl, fixed);
                AppBridge.call('Fixup', 'finish', { text: replacedText }).catch(function () {});
            });
        });
    }

    // ---- Escape key closes modals ----
    document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') {
            closeModal('themeModal');
            closeModal('historyModal');
            closeModal('qrModal');
            closeModal('notifyModal');
            closeModal('syncModal');
            closeModal('tourModal');
            closeModal('bugModal');
        }
    });
});

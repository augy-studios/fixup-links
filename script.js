/* uwuFix - client-side URL cleaner & embed fixer */
'use strict';

// ===== CONSTANTS =====
const HISTORY_KEY = 'uwufix_history';
const THEME_KEY = 'uwufix_theme';
const MAX_HISTORY = 100;

// ===== TRACKING PARAMETERS =====
// Universal trackers removed from any URL
const UNIVERSAL_TRACKERS = new Set([
    // UTM
    'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
    'utm_id', 'utm_reader', 'utm_name', 'utm_social', 'utm_social-type',
    // Click IDs
    'fbclid', 'gclid', 'gclsrc', 'msclkid', 'dclid', 'yclid', 'twclid', 'mc_eid',
    'igshid', 'li_fat_id', 'ttclid', 'ScCid', 's_cid', 'SNKRHSP',
    // General
    'ref', 'ref_src', 'ref_url', 'referral', 'source', 'srsltid',
    'icid', 'cid', 'eid', 'pid', 'sid', 'rid', 'uid', 'vid',
    '_ga', '_gl', '_hsenc', '_hsmi', 'hsa_acc', 'hsa_ad', 'hsa_cam', 'hsa_grp',
    'hsa_kw', 'hsa_mt', 'hsa_net', 'hsa_src', 'hsa_tgt', 'hsa_ver',
    'mibextid', 'mbid', 'ml_subscriber', 'ml_subscriber_hash',
    'WT.mc_id', 'WT.srch', 'affiliate', 'aff_id', 'aff_sub',
    'trk', 'track', 'tracking', 'trksid',
]);

// Platform-specific parameter sets
const PLATFORM_TRACKERS = {
    'twitter.com': new Set([
        's', 't', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
        'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url',
    ]),
    'x.com': new Set([
        's', 't', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
        'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url',
    ]),
    'instagram.com': new Set([
        'igshid', 'ig_rid', 'ig_mid', 'stp', 'smid', 'hl',
        'img_index', 'taken-by',
    ]),
    'facebook.com': new Set([
        '__cft__', '__tn__', '__xts__', 'hc_ref', 'fref', 'rc',
        'theater', 'refsrc', 'source', '_rdr',
    ]),
    'fb.com': new Set(['__cft__', '__tn__', '__xts__']),
    'youtube.com': new Set([
        'feature', 'app', 'list', 'index', 'pp', 'si', 'ab_channel',
        'cbrd', 'ucbcb', 'pbc', 'pbj',
    ]),
    'youtu.be': new Set(['feature', 'si']),
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
        'trk', 'trkInfo', 'trk_sid', 'originalSubdomain', 'refId',
        'lipi', 'licu', 'lici', 'sharer', 'trackingId',
    ]),
    'amazon.com': new Set([
        'ref', 'ref_', 'pf_rd_r', 'pf_rd_p', 'pf_rd_i', 'pf_rd_m', 'pf_rd_s', 'pf_rd_t',
        'pd_rd_r', 'pd_rd_w', 'pd_rd_wg', '_encoding', 'smid', 'sprefix', 'sr',
        'ie', 'qid', 'rps', 'linkCode', 'linkId', 'ascsubtag', 'tag',
        'creative', 'creativeASIN',
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
    'pinterest.com': new Set(['sent_episod', 'amp', 'nic']),
    'snapchat.com': new Set(['sc_referrer', 'share_id']),
    'ebay.com': new Set([
        'mkevt', 'mkcid', 'mkrid', 'campid', 'toolid', 'customid',
        'epid', 'hash', '_trkparms', '_trksid',
    ]),
    'aliexpress.com': new Set([
        'aff_platform', 'aff_trace_key', 'terminal_id', 'bizType', 'sourceType',
        'btsid', 'ws_ab_test', 'initiative_id', 'origin_design_token',
    ]),
    'spotify.com': new Set([
        'si', 'context', 'nd',
    ]),
    'threads.net': new Set([
        'igshid', 'mibextid',
    ]),
};

// ===== EMBED CONVERSION RULES =====
// Maps original hostname -> [match_fn, convert_fn, platform_label]
const EMBED_CONVERTERS = [{
        name: 'X / Twitter',
        match: h => h === 'x.com' || h === 'twitter.com' || h === 'www.x.com' || h === 'www.twitter.com',
        convert: url => {
            url.hostname = 'fixupx.com';
            return url;
        },
    },
    {
        name: 'Instagram',
        match: h => h === 'instagram.com' || h === 'www.instagram.com',
        convert: url => {
            // Try ddinstagram first (InstaFix)
            url.hostname = 'ddinstagram.com';
            return url;
        },
    },
    {
        name: 'TikTok',
        match: h => h === 'tiktok.com' || h === 'www.tiktok.com' || h === 'vm.tiktok.com',
        convert: url => {
            url.hostname = 'vxtiktok.com';
            return url;
        },
    },
    {
        name: 'Reddit',
        match: h => h === 'reddit.com' || h === 'www.reddit.com' || h === 'old.reddit.com' || h === 'new.reddit.com',
        convert: url => {
            url.hostname = 'rxddit.com';
            if (url.hostname !== 'old.reddit.com') {
                // strip old/new subdomain paths aren't needed after hostname swap
            }
            return url;
        },
    },
    {
        name: 'Bluesky',
        match: h => h === 'bsky.app' || h === 'www.bsky.app',
        convert: url => {
            url.hostname = 'bskx.app';
            return url;
        },
    },
    {
        name: 'Discord',
        match: h => h === 'canary.discord.com' || h === 'ptb.discord.com',
        convert: url => {
            url.hostname = 'discord.com';
            return url;
        },
    },
    {
        name: 'Threads',
        match: h => h === 'threads.net' || h === 'www.threads.net',
        convert: url => {
            // No reliable embed fix for Threads as of mid-2026; just strip tracking
            return url;
        },
    },
];

// ===== GOOGLE SEARCH DESTINATION EXTRACTION =====
function extractGoogleDest(url) {
    const q = url.searchParams.get('url') ||
        url.searchParams.get('q');
    if (!q) return null;
    try {
        const dest = new URL(q);
        return dest.toString();
    } catch {
        return null;
    }
}

// ===== CORE CLEANER =====
function cleanUrl(rawInput) {
    const input = rawInput.trim();
    if (!input) throw new Error('Please enter a URL.');

    let url;
    try {
        url = new URL(input.startsWith('http') ? input : 'https://' + input);
    } catch {
        throw new Error('That doesn\'t look like a valid URL. Please include https://');
    }

    if (!['http:', 'https:'].includes(url.protocol)) {
        throw new Error('Only http:// and https:// URLs are supported.');
    }

    const hostname = url.hostname.replace(/^www\./, '');
    const changes = [];

    // 1. Google Search - extract destination
    if (hostname === 'google.com' || hostname.endsWith('.google.com')) {
        const dest = extractGoogleDest(url);
        if (dest) {
            changes.push({
                type: 'redirect',
                label: 'Extracted destination from Google Search'
            });
            return {
                cleaned: dest,
                changes,
                platform: 'Google Search',
                wasConverted: false
            };
        }
    }

    // 2. Remove platform-specific trackers
    const platformKey = Object.keys(PLATFORM_TRACKERS).find(k =>
        hostname === k || hostname.endsWith('.' + k)
    );

    const platformSet = platformKey ? PLATFORM_TRACKERS[platformKey] : null;
    const removedParams = [];

    const toDelete = [];
    for (const [key] of url.searchParams) {
        const lower = key.toLowerCase();
        if (UNIVERSAL_TRACKERS.has(key) || UNIVERSAL_TRACKERS.has(lower) ||
            (platformSet && (platformSet.has(key) || platformSet.has(lower)))) {
            toDelete.push(key);
            removedParams.push(key);
        }
    }
    toDelete.forEach(k => url.searchParams.delete(k));

    if (removedParams.length > 0) {
        changes.push({
            type: 'trackers',
            label: `Removed ${removedParams.length} tracker${removedParams.length > 1 ? 's' : ''}`,
            params: removedParams,
        });
    }

    // 3. Embed conversion
    let convertedPlatform = null;
    let wasConverted = false;

    for (const converter of EMBED_CONVERTERS) {
        if (converter.match(url.hostname)) {
            const before = url.hostname;
            const result = converter.convert(url);
            if (result.hostname !== before) {
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
    const platformLabel = convertedPlatform ||
        detectPlatform(hostname) ||
        'General';

    // 5. Clean up empty query string
    let cleaned = url.toString();
    if (cleaned.endsWith('?')) cleaned = cleaned.slice(0, -1);

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

function detectPlatform(hostname) {
    const map = {
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
        'bsky.app': 'Bluesky',
        'google.com': 'Google',
    };
    for (const [key, val] of Object.entries(map)) {
        if (hostname === key || hostname.endsWith('.' + key)) return val;
    }
    return null;
}

// ===== HISTORY =====
function loadHistory() {
    try {
        return JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]');
    } catch {
        return [];
    }
}

function saveHistory(items) {
    localStorage.setItem(HISTORY_KEY, JSON.stringify(items));
}

function addToHistory(original, cleaned, platform) {
    let history = loadHistory();
    // Remove duplicate of same cleaned URL
    history = history.filter(h => h.cleaned !== cleaned);
    const entry = {
        id: Date.now(),
        original,
        cleaned,
        platform,
        date: new Date().toISOString(),
    };
    history.unshift(entry);
    if (history.length > MAX_HISTORY) history = history.slice(0, MAX_HISTORY);
    saveHistory(history);
    return history;
}

function clearHistory() {
    localStorage.removeItem(HISTORY_KEY);
}

function formatRelativeDate(iso) {
    const now = Date.now();
    const then = new Date(iso).getTime();
    const diff = now - then;
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    if (days < 7) return `${days}d ago`;
    return new Date(iso).toLocaleDateString();
}

// ===== THEME =====
const THEMES = ['classic', 'notgreen1', 'notgreen2', 'notgreen3', 'notgreen4', 'notgreen5', 'white'];

function loadTheme() {
    return localStorage.getItem(THEME_KEY) || 'classic';
}

function applyTheme(theme) {
    document.body.setAttribute('data-theme', theme);
    document.querySelectorAll('.theme-option').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.theme === theme);
    });
    // Update theme-color meta
    const colors = {
        classic: '#ccffcc',
        notgreen1: '#ffcccc',
        notgreen2: '#ccccff',
        notgreen3: '#ffffcc',
        notgreen4: '#ffccff',
        notgreen5: '#ccffff',
        white: '#f7fff7',
    };
    document.querySelector('meta[name="theme-color"]').setAttribute('content', colors[theme] || '#ccffcc');
    localStorage.setItem(THEME_KEY, theme);
}

// ===== TOAST =====
let toastTimer;

function showToast(msg) {
    const toast = document.getElementById('toast');
    toast.textContent = msg;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 2200);
}

// ===== MODALS =====
function openModal(id) {
    document.getElementById(id).classList.add('open');
    document.body.style.overflow = 'hidden';
}

function closeModal(id) {
    document.getElementById(id).classList.remove('open');
    document.body.style.overflow = '';
}

// ===== UI RENDERING =====
function renderChangeTags(changes) {
    const container = document.getElementById('changesSummary');
    container.innerHTML = '';
    changes.forEach(c => {
        const tag = document.createElement('span');
        tag.className = 'change-tag';

        let svgHtml = '';
        if (c.type === 'trackers') {
            svgHtml = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/></svg>`;
        } else if (c.type === 'embed') {
            svgHtml = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>`;
        } else if (c.type === 'redirect') {
            svgHtml = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5l7 7-7 7"/></svg>`;
        } else {
            svgHtml = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`;
        }

        tag.innerHTML = svgHtml + c.label;
        container.appendChild(tag);
    });
}

function renderHistoryList() {
    const history = loadHistory();
    const list = document.getElementById('historyList');
    const badge = document.getElementById('historyCountBadge');

    badge.textContent = history.length;

    // Remove only history items, preserve the empty-state element
    list.querySelectorAll('.history-item').forEach(el => el.remove());

    const empty = document.getElementById('historyEmpty');
    if (history.length === 0) {
        if (empty) empty.hidden = false;
        return;
    }

    if (empty) empty.hidden = true;

    history.forEach(entry => {
        const item = document.createElement('div');
        item.className = 'history-item';
        item.setAttribute('role', 'button');
        item.setAttribute('tabindex', '0');
        item.setAttribute('aria-label', `Load: ${entry.cleaned}`);

        item.innerHTML = `
      <div class="history-item-original-label">Original</div>
      <div class="history-item-original">${escapeHtml(entry.original)}</div>
      <div class="history-item-cleaned">${escapeHtml(entry.cleaned)}</div>
      <div class="history-item-meta">
        <span class="history-item-date">${formatRelativeDate(entry.date)}</span>
        <span class="history-item-platform">${escapeHtml(entry.platform)}</span>
      </div>
    `;

        item.addEventListener('click', () => {
            document.getElementById('urlInput').value = entry.original;
            closeModal('historyModal');
            document.getElementById('urlInput').focus();
            showToast('URL loaded from history');
        });

        item.addEventListener('keydown', e => {
            if (e.key === 'Enter' || e.key === ' ') item.click();
        });

        list.appendChild(item);
    });
}

function escapeHtml(str) {
    return str
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

// ===== MAIN PROCESS =====
function processUrl() {
    const input = document.getElementById('urlInput').value.trim();
    const resultArea = document.getElementById('resultArea');
    const errorArea = document.getElementById('errorArea');
    const resultUrl = document.getElementById('resultUrl');
    const errorMsg = document.getElementById('errorMsg');

    resultArea.hidden = true;
    errorArea.hidden = true;

    if (!input) {
        errorMsg.textContent = 'Please enter a URL first.';
        errorArea.hidden = false;
        return;
    }

    try {
        const {
            cleaned,
            changes,
            platform
        } = cleanUrl(input);

        resultUrl.textContent = cleaned;
        renderChangeTags(changes);
        resultArea.hidden = false;

        // Save to history
        addToHistory(input, cleaned, platform);
        renderHistoryList();

        // Store cleaned URL for action buttons
        window._uwufixLastCleaned = cleaned;

    } catch (err) {
        errorMsg.textContent = err.message;
        errorArea.hidden = false;
    }
}

// ===== CLIPBOARD =====
async function pasteFromClipboard() {
    try {
        const text = await navigator.clipboard.readText();
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
        const ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.opacity = '0';
        document.body.appendChild(ta);
        ta.select();
        document.execCommand('copy');
        document.body.removeChild(ta);
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
document.addEventListener('DOMContentLoaded', () => {
    // Apply saved theme
    applyTheme(loadTheme());
    renderHistoryList();

    // ---- Theme modal ----
    document.getElementById('openThemeModal').addEventListener('click', () => openModal('themeModal'));
    document.getElementById('closeThemeModal').addEventListener('click', () => closeModal('themeModal'));
    document.getElementById('themeModal').addEventListener('click', e => {
        if (e.target === e.currentTarget) closeModal('themeModal');
    });

    document.querySelectorAll('.theme-option').forEach(btn => {
        btn.addEventListener('click', () => {
            applyTheme(btn.dataset.theme);
            closeModal('themeModal');
            showToast('Theme applied');
        });
    });

    // ---- History modal ----
    document.getElementById('openHistoryModal').addEventListener('click', () => {
        renderHistoryList();
        openModal('historyModal');
    });
    document.getElementById('closeHistoryModal').addEventListener('click', () => closeModal('historyModal'));
    document.getElementById('historyModal').addEventListener('click', e => {
        if (e.target === e.currentTarget) closeModal('historyModal');
    });
    document.getElementById('clearHistoryBtn').addEventListener('click', () => {
        if (confirm('Clear all history?')) {
            clearHistory();
            renderHistoryList();
            showToast('History cleared');
        }
    });

    // ---- Clean button ----
    document.getElementById('cleanBtn').addEventListener('click', processUrl);

    // Allow Enter in the input
    document.getElementById('urlInput').addEventListener('keydown', e => {
        if (e.key === 'Enter') processUrl();
    });

    // ---- Paste / Clear input ----
    document.getElementById('pasteBtn').addEventListener('click', pasteFromClipboard);
    document.getElementById('clearInputBtn').addEventListener('click', () => {
        document.getElementById('urlInput').value = '';
        document.getElementById('resultArea').hidden = true;
        document.getElementById('errorArea').hidden = true;
        window._uwufixLastCleaned = null;
        document.getElementById('urlInput').focus();
    });

    // ---- Result actions ----
    document.getElementById('copyBtn').addEventListener('click', () => {
        const url = window._uwufixLastCleaned;
        if (url) copyToClipboard(url);
    });

    document.getElementById('openBtn').addEventListener('click', () => {
        const url = window._uwufixLastCleaned;
        if (url) window.open(url, '_blank', 'noopener,noreferrer');
    });

    document.getElementById('shareBtn').addEventListener('click', () => {
        const url = window._uwufixLastCleaned;
        if (url) shareUrl(url);
    });

    // ---- Auto-paste if URL in query string ----
    const qp = new URLSearchParams(window.location.search);
    const qUrl = qp.get('url');
    if (qUrl) {
        document.getElementById('urlInput').value = qUrl;
        setTimeout(processUrl, 100);
    }

    // ---- Escape key closes modals ----
    document.addEventListener('keydown', e => {
        if (e.key === 'Escape') {
            closeModal('themeModal');
            closeModal('historyModal');
        }
    });
});

// ===== SERVICE WORKER REGISTRATION =====
if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js').catch(() => {});
    });
}
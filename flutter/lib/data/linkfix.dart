// The link cleaner, ported from the site's main-site/script.js with its lists, names and words
// unchanged, so a link comes out of the app exactly as it does out of the site. The site stays the
// specification: test/linkfix_test.dart checks every list here against script.js's own, and the
// results against script.js's own results (tool/linkfix_expected.mjs), so a change made there
// and forgotten here fails a test.
//
// URLs are taken apart and put back together the way a browser's URL API does it (WhatwgUrl),
// not as Dart's Uri would: script.js leaves a query untouched until it deletes or sets a
// parameter, and then writes it back as URLSearchParams does.

/// Any parameter whose name starts with one of these is a tracker, on every host.
const trackerPrefixes = ['utm_', '_branch_'];

/// Universal trackers removed from any URL. Lowercase: keys are compared lowercased.
const universalTrackers = {
  // UTM (the utm_ prefix rule covers the rest)
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
  // AMP page selector: the canonical page is what should be shared.
  'amp',
  // Google app share tag.
  'shem',
  // Klaviyo
  '_kx', 'kx', 'tw_source',
  // Triple Whale ad attribution (Shopify stores)
  'tw_adid', 'tw_campaign', 'tw_kwdid',
  // Branch.io attribution keys without the _branch_ prefix. Routing params ($deeplink_path,
  // $fallback_url, ...) are left alone.
  '~channel', '~feature', '~campaign', '~tags', '~stage', '~creation_source',
  '~click_id', '~referring_link', '~id', '~secondary_publisher',
  r'$3p', r'$original_url', r'$identity_id', r'$s2s',
};

const _xTrackers = {
  's', 't', 'a', 'twsrc', 'twcamp', 'twterm', 'twgr', 'twcon',
  'src', 'original_referer', 'pc', 'lang', 'cxt', 'ref_src', 'ref_url',
};
const _fbTrackers = {
  '__cft__', '__tn__', '__xts__', 'hc_ref', 'fref', 'rc',
  'theater', 'refsrc', 'source', '_rdr',
  'referral_source', 'surface_type', 'in_reels_tab_context',
};
const _threadsTrackers = {'igshid', 'igsh', 'igsi', 'mibextid', 'xmt', 'slof'};

/// Platform-specific parameter sets, by host. Lowercase.
const platformTrackers = <String, Set<String>>{
  'twitter.com': _xTrackers,
  'x.com': _xTrackers,
  'instagram.com': {'igshid', 'igsh', 'igsi', 'ig_rid', 'ig_mid', 'stp', 'smid', 'hl', 'taken-by'},
  'facebook.com': _fbTrackers,
  'fb.com': _fbTrackers,
  'youtube.com': {'feature', 'app', 'list', 'index', 'pp', 'si', 'is', 'ab_channel', 'cbrd', 'ucbcb', 'pbc', 'pbj'},
  'youtu.be': {'feature', 'si', 'is'},
  'tiktok.com': {
    '_d', 'checksum', 'is_copy_url', 'is_from_webapp',
    'sender_device', 'sender_web_id', 'share_app_id', 'share_link_id',
    'tt_from', 'tt_medium', 'tt_campaign', 'tiktok_share_from',
    'source_ref', 'sec_uid', '_r',
  },
  'reddit.com': {'utm_name', 'ref_source', 'ref', 'context', 'share_id', 'post_fullname', 'cid', 'subreddit_id', 'post_index'},
  'linkedin.com': {'trk', 'trkinfo', 'trk_sid', 'originalsubdomain', 'refid', 'lipi', 'licu', 'lici', 'sharer', 'trackingid', 'rcm'},
  'amazon.com': {
    'ref', 'ref_', 'pf_rd_r', 'pf_rd_p', 'pf_rd_i', 'pf_rd_m', 'pf_rd_s', 'pf_rd_t',
    'pd_rd_r', 'pd_rd_w', 'pd_rd_wg', '_encoding', 'smid', 'sprefix', 'sr',
    'ie', 'qid', 'rps', 'linkcode', 'linkid', 'ascsubtag', 'tag',
    'creative', 'creativeasin',
  },
  'google.com': {'ved', 'usg', 'ei', 'sei', 'sa', 'sqi', 'sourceid', 'client', 'channel', 'rlz', 'oq'},
  'substack.com': {'r', 'utm_source', 'utm_medium', 'utm_campaign', 'publication_id', 'post_id'},
  'github.com': {'ref', 'notification_referrer_id', 'bpo'},
  'discord.com': {'ref', 'source'},
  'pinterest.com': {'sent_episod', 'nic'},
  'snapchat.com': {'sc_referrer', 'share_id'},
  'ebay.com': {'mkevt', 'mkcid', 'mkrid', 'campid', 'toolid', 'customid', 'epid', 'hash', '_trkparms', '_trksid'},
  'aliexpress.com': {
    'aff_platform', 'aff_trace_key', 'terminal_id', 'biztype', 'sourcetype',
    'btsid', 'ws_ab_test', 'initiative_id', 'origin_design_token',
  },
  'spotify.com': {'si', 'context', 'nd'},
  'threads.net': _threadsTrackers,
  'threads.com': _threadsTrackers,
  'twitch.tv': {'tt_content', 'tt_medium', 'sr', 'filter', 'referrer'},
  'pixiv.net': {'lang'},
  'tumblr.com': {'is_related_post', 'source'},
  'bilibili.com': {
    'spm_id_from', 'vd_source', 'from_source', 'share_source',
    'share_medium', 'share_plat', 'share_session_id', 'share_tag',
    'timestamp', 'unique_k', 'bbid', 'ts',
  },
  'bsky.app': {'ref_src', 'ref_url'},
  'eightfold.ai': {'domain', 'hl'},
  'community.samsung.com': {'src'},
};

/// Platform trackers matched by shape, for keys a platform rotates faster than a list keeps up.
final platformTrackerPatterns = <String, RegExp>{
  // Instagram share links carry a random four-letter key; ?next= is the only one a link needs.
  'instagram.com': RegExp(r'^(?!next$)[a-z]{4}$'),
};

/// Workday job postings: the whole query string goes, on /job/ pages only.
const stripAllParamHosts = ['myworkdayjobs.com', 'myworkdaysite.com'];
const stripAllParamPath = '/job/';

bool stripsAllParams(String hostname, String pathname) =>
    stripAllParamHosts.any((h) => hostname == h || hostname.endsWith('.$h')) && pathname.contains(stripAllParamPath);

/// The Mastodon instances FxMastodon covers.
const mastodonInstances = [
  'mastodon.social', 'mstdn.jp', 'mastodon.cloud', 'mstdn.social',
  'mastodon.world', 'mastodon.online', 'mas.to', 'techhub.social',
  'mastodon.uno', 'infosec.exchange',
];

class _Converter {
  const _Converter(this.name, this.match, this.convert);
  final String name;
  final bool Function(String host) match;
  final void Function(WhatwgUrl url) convert;
}

final _converters = <_Converter>[
  _Converter('X / Twitter', (h) => h == 'x.com' || h == 'twitter.com' || h == 'www.x.com' || h == 'www.twitter.com', (url) {
    url.hostname = 'fixupx.com';
    final status = RegExp(r'^/[^/]+/(status/\d+)$').firstMatch(url.pathname);
    if (status != null) url.pathname = '/i/${status.group(1)}';
  }),
  _Converter('Instagram', (h) => h == 'instagram.com' || h == 'www.instagram.com', (url) => url.hostname = 'www.oginstagram.com'),
  _Converter('YouTube', (h) => h == 'youtube.com' || h == 'www.youtube.com' || h == 'm.youtube.com', (url) {
    if (RegExp(r'^/shorts/').hasMatch(url.pathname)) url.hostname = 'koutube.com';
  }),
  _Converter('TikTok', (h) => h == 'tiktok.com' || h == 'www.tiktok.com' || h == 'vm.tiktok.com' || h == 'vt.tiktok.com', (url) {
    url.hostname = url.hostname.replaceFirst(RegExp(r'^www\.'), '').replaceFirst(RegExp(r'tiktok\.com$'), 'tnktok.com');
  }),
  _Converter('Facebook', (h) => h == 'facebook.com' || h == 'www.facebook.com' || h == 'fb.com' || h == 'www.fb.com' || h == 'm.facebook.com',
      (url) => url.hostname = 'www.facebed.com'),
  _Converter('Reddit', (h) => h == 'reddit.com' || h == 'www.reddit.com' || h == 'old.reddit.com' || h == 'new.reddit.com',
      (url) => url.hostname = 'www.vxreddit.com'),
  _Converter('Discord', (h) => h == 'canary.discord.com' || h == 'ptb.discord.com', (url) => url.hostname = 'discord.com'),
  _Converter('Threads', (h) => h == 'threads.net' || h == 'www.threads.net' || h == 'threads.com' || h == 'www.threads.com',
      (url) => url.hostname = 'fixthreads.seria.moe'),
  _Converter('Bluesky', (h) => h == 'bsky.app' || h == 'www.bsky.app', (url) => url.hostname = 'fxbsky.app'),
  _Converter('Twitch', (h) => h == 'twitch.tv' || h == 'www.twitch.tv' || h == 'm.twitch.tv', (url) => url.hostname = 'fxtwitch.seria.moe'),
  _Converter('Spotify', (h) => h == 'open.spotify.com' || h == 'spotify.com' || h == 'www.spotify.com', (url) {
    if (!RegExp(r'^(/intl-[^/]+)?/(album|prerelease)/').hasMatch(url.pathname)) url.hostname = 'fxspotify.com';
  }),
  _Converter('Pixiv', (h) => h == 'pixiv.net' || h == 'www.pixiv.net', (url) => url.hostname = 'phixiv.net'),
  _Converter('Tumblr', (h) => h == 'tumblr.com' || h == 'www.tumblr.com', (url) => url.hostname = 'tpmblr.com'),
  _Converter('BiliBili', (h) => h == 'bilibili.com' || h == 'www.bilibili.com' || h == 'm.bilibili.com', (url) => url.hostname = 'vxbilibili.com'),
  _Converter('DeviantArt', (h) => h == 'deviantart.com' || h == 'www.deviantart.com', (url) {
    if (RegExp(r'^/[^/]+/(art|journal)/[^/]+').hasMatch(url.pathname)) url.hostname = 'fixdeviantart.com';
  }),
  _Converter('Newgrounds', (h) => h == 'newgrounds.com' || h == 'www.newgrounds.com', (url) {
    if (RegExp(r'^/art/view/[^/]+/[^/]+').hasMatch(url.pathname)) url.hostname = 'fixnewgrounds.com';
  }),
  _Converter('Fur Affinity', (h) => h == 'furaffinity.net' || h == 'www.furaffinity.net', (url) {
    if (RegExp(r'^/view/[^/]+').hasMatch(url.pathname)) url.hostname = 'xfuraffinity.net';
  }),
  _Converter('Mastodon', (h) => mastodonInstances.contains(h.replaceFirst(RegExp(r'^www\.'), '')), (url) {
    if (RegExp(r'^/@[^/]+/[^/]+').hasMatch(url.pathname)) {
      url.pathname = '/${url.hostname.replaceFirst(RegExp(r'^www\.'), '')}${url.pathname}';
      url.hostname = 'fx.zillanlabs.tech';
    }
  }),
];

/// The names script.js's EMBED_CONVERTERS have, in order, for the parity test.
List<String> get converterNames => [for (final c in _converters) c.name];

const _platformNames = <String, String>{
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

String? detectPlatform(String hostname) {
  for (final e in _platformNames.entries) {
    if (hostname == e.key || hostname.endsWith('.${e.key}')) return e.value;
  }
  if (mastodonInstances.contains(hostname)) return 'Mastodon';
  return null;
}

bool isTrackerParam(String key, Set<String>? platformSet, RegExp? platformPattern) {
  final lower = key.toLowerCase();
  if (trackerPrefixes.any(lower.startsWith)) return true;
  if (universalTrackers.contains(lower)) return true;
  if (platformPattern != null && platformPattern.hasMatch(lower)) return true;
  return platformSet != null && platformSet.contains(lower);
}

/// One change cleanUrl made, as the site's change tags show it.
class Change {
  const Change(this.type, this.label, [this.params = const []]);

  /// "trackers", "embed", "redirect" or "clean".
  final String type;
  final String label;
  final List<String> params;

  Map<String, Object?> toJson() => {'type': type, 'label': label, if (params.isNotEmpty) 'params': params};
}

class CleanResult {
  const CleanResult(this.cleaned, this.changes, this.platform, this.wasConverted);
  final String cleaned;
  final List<Change> changes;
  final String platform;
  final bool wasConverted;
}

class LinkFixError implements Exception {
  const LinkFixError(this.message);
  final String message;
  @override
  String toString() => message;
}

String? _extractGoogleDest(WhatwgUrl url) {
  final q = url.getParam('url') ?? url.getParam('q');
  if (q == null || q.isEmpty) return null;
  final dest = WhatwgUrl.tryParse(q);
  return dest?.href;
}

/// script.js's cleanUrl: the link without its trackers, on an embed-friendly host where there is
/// one, with what was done to it.
CleanResult cleanUrl(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) throw const LinkFixError('Please enter a URL.');

  final url = WhatwgUrl.tryParse(input.startsWith('http') ? input : 'https://$input');
  if (url == null) throw const LinkFixError("That doesn't look like a valid URL. Please include https://");
  if (url.protocol != 'http:' && url.protocol != 'https:') {
    throw const LinkFixError('Only http:// and https:// URLs are supported.');
  }

  var hostname = url.hostname.replaceFirst(RegExp(r'^www\.'), '');
  final changes = <Change>[];

  // 0. youtu.be to youtube.com, for consistency.
  if (hostname == 'youtu.be') {
    final videoId = url.pathname.replaceAll(RegExp(r'^/|/$'), '');
    if (videoId.isNotEmpty) {
      url.hostname = 'www.youtube.com';
      url.pathname = '/watch';
      url.setParam('v', videoId);
      hostname = 'youtube.com';
      changes.add(const Change('embed', 'Converted youtu.be to youtube.com'));
    }
  }

  // 0b. The mobile YouTube host, so links open the full site.
  if (url.hostname.toLowerCase() == 'm.youtube.com') {
    url.hostname = 'www.youtube.com';
    hostname = 'youtube.com';
    changes.add(const Change('embed', 'Converted m.youtube.com to www.youtube.com'));
  }

  // 1. Google Search: the destination.
  if (hostname == 'google.com' || hostname.endsWith('.google.com')) {
    final dest = _extractGoogleDest(url);
    if (dest != null) {
      changes.add(const Change('redirect', 'Extracted destination from Google Search'));
      return CleanResult(dest, changes, 'Google Search', false);
    }
  }

  // 2. Platform-specific trackers.
  String? platformKey;
  for (final k in platformTrackers.keys) {
    if (hostname == k || hostname.endsWith('.$k')) {
      platformKey = k;
      break;
    }
  }
  final platformSet = platformKey == null ? null : platformTrackers[platformKey];
  final platformPattern = platformKey == null ? null : platformTrackerPatterns[platformKey];
  final stripAll = stripsAllParams(hostname, url.pathname);
  final removed = <String>[];
  for (final key in url.paramKeys) {
    if (stripAll || isTrackerParam(key, platformSet, platformPattern)) removed.add(key);
  }
  for (final k in removed) {
    url.deleteParam(k);
  }
  if (removed.isNotEmpty) {
    changes.add(Change('trackers', 'Removed ${removed.length} tracker${removed.length > 1 ? 's' : ''}', removed));
  }

  // 3. Embed conversion.
  String? convertedPlatform;
  var wasConverted = false;
  for (final c in _converters) {
    if (c.match(url.hostname)) {
      final before = url.hostname;
      c.convert(url);
      if (url.hostname != before) {
        changes.add(Change('embed', 'Converted to embed-friendly domain (${url.hostname})'));
        convertedPlatform = c.name;
        wasConverted = true;
      }
      break;
    }
  }

  // 4. The platform, for history.
  final platformLabel = convertedPlatform ?? detectPlatform(hostname) ?? 'General';

  // 5. No empty query string left over.
  var cleaned = url.href;
  if (cleaned.endsWith('?')) cleaned = cleaned.substring(0, cleaned.length - 1);

  if (changes.isEmpty) changes.add(const Change('clean', 'URL was already clean'));
  return CleanResult(cleaned, changes, platformLabel, wasConverted);
}

/// script.js's extractUrlFromText: the first link in some text, or a bare one like
/// x.com/user/status/1, or null.
String? extractUrlFromText(String? text) {
  if (text == null || text.isEmpty) return null;
  final m = RegExp(r'https?://\S+').firstMatch(text);
  if (m != null) return m.group(0);
  final bare = text.trim();
  return RegExp(r'^[^\s/]+\.[a-z]{2,}(/\S*)?$', caseSensitive: false).hasMatch(bare) ? bare : null;
}

/// script.js's replaceLinkInText: the text with its link swapped for the fixed one.
String replaceLinkInText(String text, String? link, String fixed) {
  final at = link == null || link.isEmpty ? -1 : text.indexOf(link);
  return at == -1 ? fixed : text.substring(0, at) + fixed + text.substring(at + link!.length);
}

String _h(String s) => s.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

/// script.js's isMeaningfulRedirect: the redirect lands on another host.
bool isMeaningfulRedirect(String fromUrl, String toUrl) {
  final from = WhatwgUrl.tryParse(fromUrl), to = WhatwgUrl.tryParse(toUrl);
  if (from == null || to == null) return false;
  return _h(from.hostname) != _h(to.hostname);
}

/// script.js's urlsEquivalent: the same host and path, trailing slash aside.
bool urlsEquivalent(String a, String b) {
  final ua = WhatwgUrl.tryParse(a), ub = WhatwgUrl.tryParse(b);
  if (ua == null || ub == null) return false;
  String norm(WhatwgUrl u) => _h(u.hostname) + u.pathname.replaceFirst(RegExp(r'/$'), '');
  return norm(ua) == norm(ub);
}

/// A URL taken apart and put back as a browser's URL API does, as far as script.js needs:
/// protocol, host, port, path, query (as URLSearchParams, only rewritten once a parameter is set
/// or deleted) and fragment.
class WhatwgUrl {
  WhatwgUrl._(this.protocol, this._userinfo, this.hostname, this._port, this.pathname, this._query, this._fragment);

  final String protocol;
  final String _userinfo;
  String hostname;
  final String _port;
  String pathname;
  String? _query; // as written, without '?', or null for none
  final String? _fragment; // without '#'
  List<MapEntry<String, String>>? _params; // once read

  static const _special = {'http:': '80', 'https:': '443', 'ws:': '80', 'wss:': '443', 'ftp:': '21'};

  static WhatwgUrl? tryParse(String input) {
    final s = input.trim();
    final m = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):').firstMatch(s);
    if (m == null) return null;
    final protocol = '${m.group(1)!.toLowerCase()}:';
    var rest = s.substring(m.end).replaceAll('\\', _special.containsKey(protocol) ? '/' : '\\');
    // Tabs and newlines inside a URL are dropped, as browsers do.
    rest = rest.replaceAll(RegExp(r'[\t\n\r]'), '');
    String? fragment;
    final hash = rest.indexOf('#');
    if (hash != -1) {
      fragment = rest.substring(hash + 1);
      rest = rest.substring(0, hash);
    }
    String? query;
    if (!_special.containsKey(protocol)) {
      // Not a web link (mailto:, javascript: ...): valid as a URL, kept whole.
      final q = rest.indexOf('?');
      if (q != -1) {
        query = rest.substring(q + 1);
        rest = rest.substring(0, q);
      }
      return WhatwgUrl._(protocol, '', '', '', rest, query, fragment);
    }
    rest = rest.replaceFirst(RegExp(r'^/*'), '');
    final pathAt = rest.indexOf(RegExp(r'[/?]'));
    var authority = pathAt == -1 ? rest : rest.substring(0, pathAt);
    var tail = pathAt == -1 ? '' : rest.substring(pathAt);
    final q = tail.indexOf('?');
    if (q != -1) {
      query = tail.substring(q + 1);
      tail = tail.substring(0, q);
    }
    var userinfo = '';
    final at = authority.lastIndexOf('@');
    if (at != -1) {
      userinfo = authority.substring(0, at);
      authority = authority.substring(at + 1);
    }
    var host = authority;
    var port = '';
    final portMatch = RegExp(r':(\d*)$').firstMatch(authority);
    if (portMatch != null && !authority.startsWith('[')) {
      host = authority.substring(0, portMatch.start);
      port = portMatch.group(1)!;
    } else if (authority.startsWith('[')) {
      final close = authority.indexOf(']');
      if (close == -1) return null;
      host = authority.substring(0, close + 1);
      final after = authority.substring(close + 1);
      if (after.startsWith(':')) port = after.substring(1);
    }
    if (host.isEmpty) return null;
    host = _decodePercent(host).toLowerCase();
    if (RegExp(r'[\x00-\x20#%/:<>?@\[\\\]^|]').hasMatch(host.replaceAll(RegExp(r'^\[|\]$'), '')) && !host.startsWith('[')) return null;
    // An international domain name, as the browser shows it: Punycode.
    if (host.runes.any((r) => r > 0x7f)) {
      final ascii = _toAscii(host);
      if (ascii == null) return null;
      host = ascii;
    }
    if (port.isNotEmpty) {
      final n = int.tryParse(port);
      if (n == null || n > 65535) return null;
      port = n.toString();
      if (port == _special[protocol]) port = '';
    }
    final path = _normalisePath(tail.isEmpty ? '/' : tail);
    return WhatwgUrl._(protocol, userinfo, host, port, path, query == null ? null : _encodeQuery(query, protocol), fragment == null ? null : _encodeFragment(fragment));
  }

  static String _decodePercent(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  // Each label not in ASCII as xn-- and its Punycode (RFC 3492), as a browser's URL has it.
  static String? _toAscii(String host) {
    final labels = <String>[];
    for (final label in host.split('.')) {
      if (!label.runes.any((r) => r > 0x7f)) {
        labels.add(label);
        continue;
      }
      final code = _punycode(label.runes.toList());
      if (code == null) return null;
      labels.add('xn--$code');
    }
    return labels.join('.');
  }

  static String? _punycode(List<int> input) {
    const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
    int adapt(int delta, int points, bool first) {
      delta = first ? delta ~/ damp : delta >> 1;
      delta += delta ~/ points;
      var k = 0;
      while (delta > ((base - tMin) * tMax) >> 1) {
        delta ~/= base - tMin;
        k += base;
      }
      return k + (base - tMin + 1) * delta ~/ (delta + skew);
    }

    String digit(int d) => String.fromCharCode(d + 22 + 75 * (d < 26 ? 1 : 0));
    final out = StringBuffer();
    for (final c in input) {
      if (c < 0x80) out.writeCharCode(c);
    }
    final basic = out.length;
    var handled = basic;
    if (basic > 0) out.write('-');
    var n = 0x80, delta = 0, bias = 72;
    while (handled < input.length) {
      var m = 0x7fffffff;
      for (final c in input) {
        if (c >= n && c < m) m = c;
      }
      delta += (m - n) * (handled + 1);
      n = m;
      for (final c in input) {
        if (c < n) delta++;
        if (c == n) {
          var q = delta;
          for (var k = base;; k += base) {
            final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
            if (q < t) break;
            out.write(digit(t + (q - t) % (base - t)));
            q = (q - t) ~/ (base - t);
          }
          out.write(digit(q));
          bias = adapt(delta, handled + 1, handled == basic);
          delta = 0;
          handled++;
        }
      }
      delta++;
      n++;
    }
    return out.toString();
  }

  // The path as a browser writes it: dot segments resolved, and what may not be in a path
  // percent-encoded (spaces, quotes, angle brackets, braces, backticks, and anything not ASCII).
  static String _normalisePath(String path) {
    final segments = path.split('/');
    final out = <String>[];
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final last = i == segments.length - 1;
      final lower = seg.toLowerCase();
      if (lower == '.' || lower == '%2e') {
        if (last) out.add('');
        continue;
      }
      if (lower == '..' || lower == '.%2e' || lower == '%2e.' || lower == '%2e%2e') {
        if (out.length > 1) out.removeLast();
        if (last) out.add('');
        continue;
      }
      out.add(seg);
    }
    var joined = out.join('/');
    if (!joined.startsWith('/')) joined = '/$joined';
    return _encodeSet(joined, const {0x20, 0x22, 0x23, 0x3C, 0x3E, 0x3F, 0x60, 0x7B, 0x7D});
  }

  static String _encodeQuery(String q, String protocol) =>
      _encodeSet(q, {0x20, 0x22, 0x23, 0x3C, 0x3E, if (_special.containsKey(protocol)) 0x27});

  static String _encodeFragment(String f) => _encodeSet(f, const {0x20, 0x22, 0x3C, 0x3E, 0x60});

  // Percent-encodes C0 controls, anything above ASCII (as UTF-8), and the set given.
  static String _encodeSet(String s, Set<int> set) {
    final b = StringBuffer();
    for (final rune in s.runes) {
      if (rune < 0x20 || rune > 0x7e || set.contains(rune)) {
        for (final byte in _utf8(rune)) {
          b.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      } else {
        b.writeCharCode(rune);
      }
    }
    return b.toString();
  }

  static List<int> _utf8(int rune) {
    if (rune < 0x80) return [rune];
    if (rune < 0x800) return [0xC0 | (rune >> 6), 0x80 | (rune & 0x3F)];
    if (rune < 0x10000) return [0xE0 | (rune >> 12), 0x80 | ((rune >> 6) & 0x3F), 0x80 | (rune & 0x3F)];
    return [0xF0 | (rune >> 18), 0x80 | ((rune >> 12) & 0x3F), 0x80 | ((rune >> 6) & 0x3F), 0x80 | (rune & 0x3F)];
  }

  // ---------- URLSearchParams ----------

  List<MapEntry<String, String>> get _list => _params ??= _parseParams(_query ?? '');

  static List<MapEntry<String, String>> _parseParams(String q) {
    final out = <MapEntry<String, String>>[];
    for (final part in q.split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      final k = eq == -1 ? part : part.substring(0, eq);
      final v = eq == -1 ? '' : part.substring(eq + 1);
      out.add(MapEntry(_formDecode(k), _formDecode(v)));
    }
    return out;
  }

  // application/x-www-form-urlencoded's decoding: + is a space, and %XX a byte, leniently.
  static String _formDecode(String s) {
    final bytes = <int>[];
    final src = s.replaceAll('+', ' ');
    final units = src.codeUnits;
    for (var i = 0; i < units.length; i++) {
      final c = units[i];
      if (c == 0x25 && i + 2 < units.length) {
        final pair = src.substring(i + 1, i + 3);
        if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(pair)) {
          bytes.add(int.parse(pair, radix: 16));
          i += 2;
          continue;
        }
      }
      if (c < 0x80) {
        bytes.add(c);
      } else {
        // Not ASCII: its UTF-8, taking surrogate pairs whole.
        var rune = c;
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < units.length) {
          final lo = units[i + 1];
          if (lo >= 0xDC00 && lo <= 0xDFFF) {
            rune = 0x10000 + ((c - 0xD800) << 10) + (lo - 0xDC00);
            i++;
          }
        }
        bytes.addAll(_utf8(rune));
      }
    }
    return _utf8Decode(bytes);
  }

  static String _utf8Decode(List<int> bytes) {
    try {
      return const Utf8Lenient().convert(bytes);
    } catch (_) {
      return String.fromCharCodes(bytes);
    }
  }

  // URLSearchParams' serialising: everything but A-Z a-z 0-9 * - . _ encoded, spaces as +.
  static String _formEncode(String s) {
    final b = StringBuffer();
    for (final rune in s.runes) {
      if (rune == 0x20) {
        b.write('+');
      } else if ((rune >= 0x30 && rune <= 0x39) || (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A) || rune == 0x2A || rune == 0x2D || rune == 0x2E || rune == 0x5F) {
        b.writeCharCode(rune);
      } else {
        for (final byte in _utf8(rune)) {
          b.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
    }
    return b.toString();
  }

  void _rewrite() {
    final list = _list;
    _query = list.isEmpty ? null : list.map((e) => '${_formEncode(e.key)}=${_formEncode(e.value)}').join('&');
  }

  /// Every key, in order, repeats and all (URLSearchParams' iteration).
  List<String> get paramKeys => [for (final e in _list) e.key];

  String? getParam(String key) {
    for (final e in _list) {
      if (e.key == key) return e.value;
    }
    return null;
  }

  void deleteParam(String key) {
    _list.removeWhere((e) => e.key == key);
    _rewrite();
  }

  void setParam(String key, String value) {
    final list = _list;
    final i = list.indexWhere((e) => e.key == key);
    if (i == -1) {
      list.add(MapEntry(key, value));
    } else {
      list[i] = MapEntry(key, value);
      for (var j = list.length - 1; j > i; j--) {
        if (list[j].key == key) list.removeAt(j);
      }
    }
    _rewrite();
  }

  String get host => _port.isEmpty ? hostname : '$hostname:$_port';

  String get href {
    if (!_special.containsKey(protocol)) {
      return '$protocol$pathname${_query == null ? '' : '?$_query'}${_fragment == null ? '' : '#$_fragment'}';
    }
    final auth = _userinfo.isEmpty ? '' : '$_userinfo@';
    return '$protocol//$auth$host$pathname${_query == null ? '' : '?$_query'}${_fragment == null ? '' : '#$_fragment'}';
  }

  @override
  String toString() => href;
}

/// UTF-8 that never throws: a bad sequence becomes U+FFFD, as browsers decode it.
class Utf8Lenient {
  const Utf8Lenient();
  String convert(List<int> bytes) {
    final b = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final c = bytes[i];
      int need, rune;
      if (c < 0x80) {
        b.writeCharCode(c);
        i++;
        continue;
      } else if (c >= 0xC2 && c <= 0xDF) {
        need = 1;
        rune = c & 0x1F;
      } else if (c >= 0xE0 && c <= 0xEF) {
        need = 2;
        rune = c & 0x0F;
      } else if (c >= 0xF0 && c <= 0xF4) {
        need = 3;
        rune = c & 0x07;
      } else {
        b.writeCharCode(0xFFFD);
        i++;
        continue;
      }
      if (i + need >= bytes.length) {
        b.writeCharCode(0xFFFD);
        i++;
        continue;
      }
      var ok = true;
      for (var k = 1; k <= need; k++) {
        final n = bytes[i + k];
        if (n & 0xC0 != 0x80) {
          ok = false;
          break;
        }
        rune = (rune << 6) | (n & 0x3F);
      }
      if (!ok) {
        b.writeCharCode(0xFFFD);
        i++;
        continue;
      }
      b.writeCharCode(rune);
      i += need + 1;
    }
    return b.toString();
  }
}

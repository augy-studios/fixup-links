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
const _facebookTrackers = {
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
  'facebook.com': _facebookTrackers,
  'fb.com': _facebookTrackers,
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
const stripAllParameterHosts = ['myworkdayjobs.com', 'myworkdaysite.com'];
const stripAllParameterPath = '/job/';

/// Whether a Workday job page's whole query string goes (script.js's stripsAllParameters).
bool stripsAllParameters(String hostname, String pathname) {
  var onStripAllHost = false;
  for (final stripHost in stripAllParameterHosts) {
    if (hostname == stripHost || hostname.endsWith('.$stripHost')) {
      onStripAllHost = true;
      break;
    }
  }
  return onStripAllHost && pathname.contains(stripAllParameterPath);
}

/// The Mastodon instances FxMastodon covers.
const mastodonInstances = [
  'mastodon.social', 'mstdn.jp', 'mastodon.cloud', 'mstdn.social',
  'mastodon.world', 'mastodon.online', 'mas.to', 'techhub.social',
  'mastodon.uno', 'infosec.exchange',
];

/// One of script.js's EMBED_CONVERTERS: a platform's name, which hosts it covers, and how it
/// moves a link to the embed-friendly host.
class _Converter {
  const _Converter(this.name, this.match, this.convert);
  final String name;
  final bool Function(String host) match;
  final void Function(WhatwgUrl url) convert;
}

final _converters = <_Converter>[
  _Converter('X / Twitter', (host) {
    return host == 'x.com' || host == 'twitter.com' || host == 'www.x.com' || host == 'www.twitter.com';
  }, (url) {
    url.hostname = 'fixupx.com';
    final status = RegExp(r'^/[^/]+/(status/\d+)$').firstMatch(url.pathname);
    if (status != null) {
      url.pathname = '/i/${status.group(1)}';
    }
  }),
  _Converter('Instagram', (host) {
    return host == 'instagram.com' || host == 'www.instagram.com';
  }, (url) {
    url.hostname = 'www.oginstagram.com';
  }),
  _Converter('YouTube', (host) {
    return host == 'youtube.com' || host == 'www.youtube.com' || host == 'm.youtube.com';
  }, (url) {
    if (RegExp(r'^/shorts/').hasMatch(url.pathname)) {
      url.hostname = 'koutube.com';
    }
  }),
  _Converter('TikTok', (host) {
    return host == 'tiktok.com' || host == 'www.tiktok.com' || host == 'vm.tiktok.com' || host == 'vt.tiktok.com';
  }, (url) {
    url.hostname = url.hostname.replaceFirst(RegExp(r'^www\.'), '').replaceFirst(RegExp(r'tiktok\.com$'), 'tnktok.com');
  }),
  _Converter('Facebook', (host) {
    return host == 'facebook.com' || host == 'www.facebook.com' || host == 'fb.com' || host == 'www.fb.com' || host == 'm.facebook.com';
  }, (url) {
    url.hostname = 'www.facebed.com';
  }),
  _Converter('Reddit', (host) {
    return host == 'reddit.com' || host == 'www.reddit.com' || host == 'old.reddit.com' || host == 'new.reddit.com';
  }, (url) {
    url.hostname = 'www.vxreddit.com';
  }),
  _Converter('Discord', (host) {
    return host == 'canary.discord.com' || host == 'ptb.discord.com';
  }, (url) {
    url.hostname = 'discord.com';
  }),
  _Converter('Threads', (host) {
    return host == 'threads.net' || host == 'www.threads.net' || host == 'threads.com' || host == 'www.threads.com';
  }, (url) {
    url.hostname = 'fixthreads.seria.moe';
  }),
  _Converter('Bluesky', (host) {
    return host == 'bsky.app' || host == 'www.bsky.app';
  }, (url) {
    url.hostname = 'fxbsky.app';
  }),
  _Converter('Twitch', (host) {
    return host == 'twitch.tv' || host == 'www.twitch.tv' || host == 'm.twitch.tv';
  }, (url) {
    url.hostname = 'fxtwitch.seria.moe';
  }),
  _Converter('Spotify', (host) {
    return host == 'open.spotify.com' || host == 'spotify.com' || host == 'www.spotify.com';
  }, (url) {
    if (!RegExp(r'^(/intl-[^/]+)?/(album|prerelease)/').hasMatch(url.pathname)) {
      url.hostname = 'fxspotify.com';
    }
  }),
  _Converter('Pixiv', (host) {
    return host == 'pixiv.net' || host == 'www.pixiv.net';
  }, (url) {
    url.hostname = 'phixiv.net';
  }),
  _Converter('Tumblr', (host) {
    return host == 'tumblr.com' || host == 'www.tumblr.com';
  }, (url) {
    url.hostname = 'tpmblr.com';
  }),
  _Converter('BiliBili', (host) {
    return host == 'bilibili.com' || host == 'www.bilibili.com' || host == 'm.bilibili.com';
  }, (url) {
    url.hostname = 'vxbilibili.com';
  }),
  _Converter('DeviantArt', (host) {
    return host == 'deviantart.com' || host == 'www.deviantart.com';
  }, (url) {
    if (RegExp(r'^/[^/]+/(art|journal)/[^/]+').hasMatch(url.pathname)) {
      url.hostname = 'fixdeviantart.com';
    }
  }),
  _Converter('Newgrounds', (host) {
    return host == 'newgrounds.com' || host == 'www.newgrounds.com';
  }, (url) {
    if (RegExp(r'^/art/view/[^/]+/[^/]+').hasMatch(url.pathname)) {
      url.hostname = 'fixnewgrounds.com';
    }
  }),
  _Converter('Fur Affinity', (host) {
    return host == 'furaffinity.net' || host == 'www.furaffinity.net';
  }, (url) {
    if (RegExp(r'^/view/[^/]+').hasMatch(url.pathname)) {
      url.hostname = 'xfuraffinity.net';
    }
  }),
  _Converter('Mastodon', (host) {
    return mastodonInstances.contains(host.replaceFirst(RegExp(r'^www\.'), ''));
  }, (url) {
    if (RegExp(r'^/@[^/]+/[^/]+').hasMatch(url.pathname)) {
      url.pathname = '/${url.hostname.replaceFirst(RegExp(r'^www\.'), '')}${url.pathname}';
      url.hostname = 'fx.zillanlabs.tech';
    }
  }),
];

/// The names script.js's EMBED_CONVERTERS have, in order, for the parity test.
List<String> get converterNames {
  final names = <String>[];
  for (final converter in _converters) {
    names.add(converter.name);
  }
  return names;
}

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

/// script.js's detectPlatform: the platform's name for a host (or one of its subdomains), or null.
String? detectPlatform(String hostname) {
  for (final platform in _platformNames.entries) {
    if (hostname == platform.key || hostname.endsWith('.${platform.key}')) {
      return platform.value;
    }
  }
  if (mastodonInstances.contains(hostname)) {
    return 'Mastodon';
  }
  return null;
}

/// script.js's isTrackerParameter: whether a query parameter is a tracker, on every host or on this
/// platform.
bool isTrackerParameter(String key, Set<String>? platformSet, RegExp? platformPattern) {
  final lower = key.toLowerCase();
  for (final prefix in trackerPrefixes) {
    if (lower.startsWith(prefix)) {
      return true;
    }
  }
  if (universalTrackers.contains(lower)) {
    return true;
  }
  if (platformPattern != null && platformPattern.hasMatch(lower)) {
    return true;
  }
  return platformSet != null && platformSet.contains(lower);
}

/// One change cleanUrl made, as the site's change tags show it.
class Change {
  const Change(this.type, this.label, [this.params = const []]);

  /// "trackers", "embed", "redirect" or "clean".
  final String type;
  final String label;
  final List<String> params;

  Map<String, Object?> toJson() {
    return {'type': type, 'label': label, if (params.isNotEmpty) 'params': params};
  }
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
  String toString() {
    return message;
  }
}

/// script.js's extractGoogleDestination: where a Google Search result link really goes (its url= or
/// q= parameter), or null.
String? _extractGoogleDestination(WhatwgUrl url) {
  String? query;
  final urlParameter = url.getParameter('url');
  if (urlParameter != null) {
    query = urlParameter;
  } else {
    query = url.getParameter('q');
  }
  if (query == null || query.isEmpty) {
    return null;
  }
  final destination = WhatwgUrl.tryParse(query);
  return destination?.href;
}

/// script.js's cleanUrl: the link without its trackers, on an embed-friendly host where there is
/// one, with what was done to it.
CleanResult cleanUrl(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) {
    throw const LinkFixError('Please enter a URL.');
  }

  String withScheme;
  if (input.startsWith('http')) {
    withScheme = input;
  } else {
    withScheme = 'https://$input';
  }
  final url = WhatwgUrl.tryParse(withScheme);
  if (url == null) {
    throw const LinkFixError("That doesn't look like a valid URL. Please include https://");
  }
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
      url.setParameter('v', videoId);
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
    final destination = _extractGoogleDestination(url);
    if (destination != null) {
      changes.add(const Change('redirect', 'Extracted destination from Google Search'));
      return CleanResult(destination, changes, 'Google Search', false);
    }
  }

  // 2. Platform-specific trackers.
  String? platformKey;
  for (final trackerHost in platformTrackers.keys) {
    if (hostname == trackerHost || hostname.endsWith('.$trackerHost')) {
      platformKey = trackerHost;
      break;
    }
  }
  Set<String>? platformSet;
  RegExp? platformPattern;
  if (platformKey != null) {
    platformSet = platformTrackers[platformKey];
    platformPattern = platformTrackerPatterns[platformKey];
  }
  final stripAll = stripsAllParameters(hostname, url.pathname);
  final removed = <String>[];
  for (final key in url.parameterKeys) {
    if (stripAll || isTrackerParameter(key, platformSet, platformPattern)) {
      removed.add(key);
    }
  }
  for (final key in removed) {
    url.deleteParameter(key);
  }
  if (removed.isNotEmpty) {
    var plural = '';
    if (removed.length > 1) {
      plural = 's';
    }
    changes.add(Change('trackers', 'Removed ${removed.length} tracker$plural', removed));
  }

  // 3. Embed conversion.
  String? convertedPlatform;
  var wasConverted = false;
  for (final converter in _converters) {
    if (converter.match(url.hostname)) {
      final before = url.hostname;
      converter.convert(url);
      if (url.hostname != before) {
        changes.add(Change('embed', 'Converted to embed-friendly domain (${url.hostname})'));
        convertedPlatform = converter.name;
        wasConverted = true;
      }
      break;
    }
  }

  // 4. The platform, for history.
  String platformLabel;
  if (convertedPlatform != null) {
    platformLabel = convertedPlatform;
  } else {
    final detected = detectPlatform(hostname);
    if (detected != null) {
      platformLabel = detected;
    } else {
      platformLabel = 'General';
    }
  }

  // 5. No empty query string left over.
  var cleaned = url.href;
  if (cleaned.endsWith('?')) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }

  if (changes.isEmpty) {
    changes.add(const Change('clean', 'URL was already clean'));
  }
  return CleanResult(cleaned, changes, platformLabel, wasConverted);
}

/// script.js's extractUrlFromText: the first link in some text, or a bare one like
/// x.com/user/status/1, or null.
String? extractUrlFromText(String? text) {
  if (text == null || text.isEmpty) {
    return null;
  }
  final match = RegExp(r'https?://\S+').firstMatch(text);
  if (match != null) {
    return match.group(0);
  }
  final bare = text.trim();
  if (RegExp(r'^[^\s/]+\.[a-z]{2,}(/\S*)?$', caseSensitive: false).hasMatch(bare)) {
    return bare;
  }
  return null;
}

/// script.js's replaceLinkInText: the text with its link swapped for the fixed one.
String replaceLinkInText(String text, String? link, String fixed) {
  var position = -1;
  if (link != null && link.isNotEmpty) {
    position = text.indexOf(link);
  }
  if (position == -1) {
    return fixed;
  }
  return text.substring(0, position) + fixed + text.substring(position + link!.length);
}

/// A host as the redirect checks compare it: lowercase, without www.
String _comparableHost(String host) {
  return host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
}

/// script.js's isMeaningfulRedirect: the redirect lands on another host.
bool isMeaningfulRedirect(String fromUrl, String toUrl) {
  final from = WhatwgUrl.tryParse(fromUrl);
  final to = WhatwgUrl.tryParse(toUrl);
  if (from == null || to == null) {
    return false;
  }
  return _comparableHost(from.hostname) != _comparableHost(to.hostname);
}

/// script.js's urlsEquivalent: the same host and path, trailing slash aside.
bool urlsEquivalent(String firstUrl, String secondUrl) {
  final first = WhatwgUrl.tryParse(firstUrl);
  final second = WhatwgUrl.tryParse(secondUrl);
  if (first == null || second == null) {
    return false;
  }
  String normalised(WhatwgUrl url) {
    return _comparableHost(url.hostname) + url.pathname.replaceFirst(RegExp(r'/$'), '');
  }

  return normalised(first) == normalised(second);
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
  List<MapEntry<String, String>>? _parameters; // once read

  /// The special schemes (web links and the like), with each one's default port.
  static const _specialSchemePorts = {'http:': '80', 'https:': '443', 'ws:': '80', 'wss:': '443', 'ftp:': '21'};

  /// The input as a browser's URL parser would read it, or null where a browser would throw:
  /// scheme, user info, host (lowercased, percent-decoded, Punycode for international names),
  /// port (dropped when it's the scheme's default), normalised path, query and fragment.
  static WhatwgUrl? tryParse(String input) {
    final trimmed = input.trim();
    final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):').firstMatch(trimmed);
    if (schemeMatch == null) {
      return null;
    }
    final protocol = '${schemeMatch.group(1)!.toLowerCase()}:';
    String backslashReplacement;
    if (_specialSchemePorts.containsKey(protocol)) {
      backslashReplacement = '/';
    } else {
      backslashReplacement = '\\';
    }
    var rest = trimmed.substring(schemeMatch.end).replaceAll('\\', backslashReplacement);
    // Tabs and newlines inside a URL are dropped, as browsers do.
    rest = rest.replaceAll(RegExp(r'[\t\n\r]'), '');
    String? fragment;
    final hashPosition = rest.indexOf('#');
    if (hashPosition != -1) {
      fragment = rest.substring(hashPosition + 1);
      rest = rest.substring(0, hashPosition);
    }
    String? query;
    if (!_specialSchemePorts.containsKey(protocol)) {
      // Not a web link (mailto:, javascript: ...): valid as a URL, kept whole.
      final questionPosition = rest.indexOf('?');
      if (questionPosition != -1) {
        query = rest.substring(questionPosition + 1);
        rest = rest.substring(0, questionPosition);
      }
      return WhatwgUrl._(protocol, '', '', '', rest, query, fragment);
    }
    rest = rest.replaceFirst(RegExp(r'^/*'), '');
    final pathPosition = rest.indexOf(RegExp(r'[/?]'));
    String authority;
    String tail;
    if (pathPosition == -1) {
      authority = rest;
      tail = '';
    } else {
      authority = rest.substring(0, pathPosition);
      tail = rest.substring(pathPosition);
    }
    final questionPosition = tail.indexOf('?');
    if (questionPosition != -1) {
      query = tail.substring(questionPosition + 1);
      tail = tail.substring(0, questionPosition);
    }
    var userinfo = '';
    final atPosition = authority.lastIndexOf('@');
    if (atPosition != -1) {
      userinfo = authority.substring(0, atPosition);
      authority = authority.substring(atPosition + 1);
    }
    var host = authority;
    var port = '';
    final portMatch = RegExp(r':(\d*)$').firstMatch(authority);
    if (portMatch != null && !authority.startsWith('[')) {
      host = authority.substring(0, portMatch.start);
      port = portMatch.group(1)!;
    } else if (authority.startsWith('[')) {
      final closePosition = authority.indexOf(']');
      if (closePosition == -1) {
        return null;
      }
      host = authority.substring(0, closePosition + 1);
      final after = authority.substring(closePosition + 1);
      if (after.startsWith(':')) {
        port = after.substring(1);
      }
    }
    if (host.isEmpty) {
      return null;
    }
    host = _decodePercent(host).toLowerCase();
    final hostWithoutBrackets = host.replaceAll(RegExp(r'^\[|\]$'), '');
    if (RegExp(r'[\x00-\x20#%/:<>?@\[\\\]^|]').hasMatch(hostWithoutBrackets) && !host.startsWith('[')) {
      return null;
    }
    // An international domain name, as the browser shows it: Punycode.
    if (_hasNonAscii(host)) {
      final ascii = _toAscii(host);
      if (ascii == null) {
        return null;
      }
      host = ascii;
    }
    if (port.isNotEmpty) {
      final portNumber = int.tryParse(port);
      if (portNumber == null || portNumber > 65535) {
        return null;
      }
      port = portNumber.toString();
      if (port == _specialSchemePorts[protocol]) {
        port = '';
      }
    }
    String path;
    if (tail.isEmpty) {
      path = _normalisePath('/');
    } else {
      path = _normalisePath(tail);
    }
    String? encodedQuery;
    if (query != null) {
      encodedQuery = _encodeQuery(query, protocol);
    }
    String? encodedFragment;
    if (fragment != null) {
      encodedFragment = _encodeFragment(fragment);
    }
    return WhatwgUrl._(protocol, userinfo, host, port, path, encodedQuery, encodedFragment);
  }

  /// Whether the text has any character outside ASCII.
  static bool _hasNonAscii(String text) {
    for (final rune in text.runes) {
      if (rune > 0x7f) {
        return true;
      }
    }
    return false;
  }

  static String _decodePercent(String text) {
    try {
      return Uri.decodeComponent(text);
    } catch (_) {
      return text;
    }
  }

  // Each label not in ASCII as xn-- and its Punycode (RFC 3492), as a browser's URL has it.
  static String? _toAscii(String host) {
    final labels = <String>[];
    for (final label in host.split('.')) {
      if (!_hasNonAscii(label)) {
        labels.add(label);
        continue;
      }
      final code = _punycode(label.runes.toList());
      if (code == null) {
        return null;
      }
      labels.add('xn--$code');
    }
    return labels.join('.');
  }

  /// Punycode's encoding of one label (RFC 3492, section 6.3): its ASCII characters as they are,
  /// a hyphen, then each other character as a variable-length number in base 36.
  static String? _punycode(List<int> input) {
    const base = 36, thresholdMinimum = 1, thresholdMaximum = 26, skew = 38, damp = 700;

    // The bias adaptation function (RFC 3492, section 6.1).
    int adapt(int delta, int points, bool first) {
      if (first) {
        delta = delta ~/ damp;
      } else {
        delta = delta >> 1;
      }
      delta += delta ~/ points;
      var baseMultiple = 0;
      while (delta > ((base - thresholdMinimum) * thresholdMaximum) >> 1) {
        delta ~/= base - thresholdMinimum;
        baseMultiple += base;
      }
      return baseMultiple + (base - thresholdMinimum + 1) * delta ~/ (delta + skew);
    }

    // A digit's character: 0-25 as a-z, 26-35 as 0-9.
    String digit(int digitValue) {
      var letterOffset = 0;
      if (digitValue < 26) {
        letterOffset = 1;
      }
      return String.fromCharCode(digitValue + 22 + 75 * letterOffset);
    }

    final output = StringBuffer();
    for (final codePoint in input) {
      if (codePoint < 0x80) {
        output.writeCharCode(codePoint);
      }
    }
    final basicCount = output.length;
    var handled = basicCount;
    if (basicCount > 0) {
      output.write('-');
    }
    var nextCodePoint = 0x80, delta = 0, bias = 72;
    while (handled < input.length) {
      var smallest = 0x7fffffff;
      for (final codePoint in input) {
        if (codePoint >= nextCodePoint && codePoint < smallest) {
          smallest = codePoint;
        }
      }
      delta += (smallest - nextCodePoint) * (handled + 1);
      nextCodePoint = smallest;
      for (final codePoint in input) {
        if (codePoint < nextCodePoint) {
          delta++;
        }
        if (codePoint == nextCodePoint) {
          var remaining = delta;
          for (var step = base;; step += base) {
            int threshold;
            if (step <= bias) {
              threshold = thresholdMinimum;
            } else if (step >= bias + thresholdMaximum) {
              threshold = thresholdMaximum;
            } else {
              threshold = step - bias;
            }
            if (remaining < threshold) {
              break;
            }
            output.write(digit(threshold + (remaining - threshold) % (base - threshold)));
            remaining = (remaining - threshold) ~/ (base - threshold);
          }
          output.write(digit(remaining));
          bias = adapt(delta, handled + 1, handled == basicCount);
          delta = 0;
          handled++;
        }
      }
      delta++;
      nextCodePoint++;
    }
    return output.toString();
  }

  // The path as a browser writes it: dot segments resolved, and what may not be in a path
  // percent-encoded (spaces, quotes, angle brackets, braces, backticks, and anything not ASCII).
  static String _normalisePath(String path) {
    final segments = path.split('/');
    final output = <String>[];
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final isLast = index == segments.length - 1;
      final lower = segment.toLowerCase();
      if (lower == '.' || lower == '%2e') {
        if (isLast) {
          output.add('');
        }
        continue;
      }
      if (lower == '..' || lower == '.%2e' || lower == '%2e.' || lower == '%2e%2e') {
        if (output.length > 1) {
          output.removeLast();
        }
        if (isLast) {
          output.add('');
        }
        continue;
      }
      output.add(segment);
    }
    var joined = output.join('/');
    if (!joined.startsWith('/')) {
      joined = '/$joined';
    }
    return _encodeSet(joined, const {0x20, 0x22, 0x23, 0x3C, 0x3E, 0x3F, 0x60, 0x7B, 0x7D});
  }

  static String _encodeQuery(String query, String protocol) {
    return _encodeSet(query, {0x20, 0x22, 0x23, 0x3C, 0x3E, if (_specialSchemePorts.containsKey(protocol)) 0x27});
  }

  static String _encodeFragment(String fragment) {
    return _encodeSet(fragment, const {0x20, 0x22, 0x3C, 0x3E, 0x60});
  }

  // Percent-encodes C0 controls, anything above ASCII (as UTF-8), and the set given.
  static String _encodeSet(String text, Set<int> encodeSet) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune < 0x20 || rune > 0x7e || encodeSet.contains(rune)) {
        for (final byte in _utf8(rune)) {
          buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  static List<int> _utf8(int rune) {
    if (rune < 0x80) {
      return [rune];
    }
    if (rune < 0x800) {
      return [0xC0 | (rune >> 6), 0x80 | (rune & 0x3F)];
    }
    if (rune < 0x10000) {
      return [0xE0 | (rune >> 12), 0x80 | ((rune >> 6) & 0x3F), 0x80 | (rune & 0x3F)];
    }
    return [0xF0 | (rune >> 18), 0x80 | ((rune >> 12) & 0x3F), 0x80 | ((rune >> 6) & 0x3F), 0x80 | (rune & 0x3F)];
  }

  // ---------- URLSearchParams ----------

  List<MapEntry<String, String>> get _parameterList {
    final existing = _parameters;
    if (existing != null) {
      return existing;
    }
    var query = '';
    if (_query != null) {
      query = _query!;
    }
    final parsed = _parseParameters(query);
    _parameters = parsed;
    return parsed;
  }

  static List<MapEntry<String, String>> _parseParameters(String query) {
    final parameters = <MapEntry<String, String>>[];
    for (final part in query.split('&')) {
      if (part.isEmpty) {
        continue;
      }
      final equalsPosition = part.indexOf('=');
      String key;
      String value;
      if (equalsPosition == -1) {
        key = part;
        value = '';
      } else {
        key = part.substring(0, equalsPosition);
        value = part.substring(equalsPosition + 1);
      }
      parameters.add(MapEntry(_formDecode(key), _formDecode(value)));
    }
    return parameters;
  }

  // application/x-www-form-urlencoded's decoding: + is a space, and %XX a byte, leniently.
  static String _formDecode(String text) {
    final bytes = <int>[];
    final source = text.replaceAll('+', ' ');
    final units = source.codeUnits;
    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      if (unit == 0x25 && index + 2 < units.length) {
        final pair = source.substring(index + 1, index + 3);
        if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(pair)) {
          bytes.add(int.parse(pair, radix: 16));
          index += 2;
          continue;
        }
      }
      if (unit < 0x80) {
        bytes.add(unit);
      } else {
        // Not ASCII: its UTF-8, taking surrogate pairs whole.
        var rune = unit;
        if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < units.length) {
          final lowSurrogate = units[index + 1];
          if (lowSurrogate >= 0xDC00 && lowSurrogate <= 0xDFFF) {
            rune = 0x10000 + ((unit - 0xD800) << 10) + (lowSurrogate - 0xDC00);
            index++;
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
  static String _formEncode(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final isDigit = rune >= 0x30 && rune <= 0x39;
      final isUpperLetter = rune >= 0x41 && rune <= 0x5A;
      final isLowerLetter = rune >= 0x61 && rune <= 0x7A;
      final isSafeMark = rune == 0x2A || rune == 0x2D || rune == 0x2E || rune == 0x5F;
      if (rune == 0x20) {
        buffer.write('+');
      } else if (isDigit || isUpperLetter || isLowerLetter || isSafeMark) {
        buffer.writeCharCode(rune);
      } else {
        for (final byte in _utf8(rune)) {
          buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
    }
    return buffer.toString();
  }

  void _rewrite() {
    final list = _parameterList;
    if (list.isEmpty) {
      _query = null;
      return;
    }
    final pairs = <String>[];
    for (final parameter in list) {
      pairs.add('${_formEncode(parameter.key)}=${_formEncode(parameter.value)}');
    }
    _query = pairs.join('&');
  }

  /// Every key, in order, repeats and all (URLSearchParams' iteration).
  List<String> get parameterKeys {
    final keys = <String>[];
    for (final parameter in _parameterList) {
      keys.add(parameter.key);
    }
    return keys;
  }

  String? getParameter(String key) {
    for (final parameter in _parameterList) {
      if (parameter.key == key) {
        return parameter.value;
      }
    }
    return null;
  }

  void deleteParameter(String key) {
    _parameterList.removeWhere((parameter) {
      return parameter.key == key;
    });
    _rewrite();
  }

  /// URLSearchParams' set: the first parameter with this key takes the value and any later ones
  /// go, or it's added at the end.
  void setParameter(String key, String value) {
    final list = _parameterList;
    final index = list.indexWhere((parameter) {
      return parameter.key == key;
    });
    if (index == -1) {
      list.add(MapEntry(key, value));
    } else {
      list[index] = MapEntry(key, value);
      for (var laterIndex = list.length - 1; laterIndex > index; laterIndex--) {
        if (list[laterIndex].key == key) {
          list.removeAt(laterIndex);
        }
      }
    }
    _rewrite();
  }

  String get host {
    if (_port.isEmpty) {
      return hostname;
    }
    return '$hostname:$_port';
  }

  String get href {
    var querySuffix = '';
    if (_query != null) {
      querySuffix = '?$_query';
    }
    var fragmentSuffix = '';
    if (_fragment != null) {
      fragmentSuffix = '#$_fragment';
    }
    if (!_specialSchemePorts.containsKey(protocol)) {
      return '$protocol$pathname$querySuffix$fragmentSuffix';
    }
    var userinfoPrefix = '';
    if (_userinfo.isNotEmpty) {
      userinfoPrefix = '$_userinfo@';
    }
    return '$protocol//$userinfoPrefix$host$pathname$querySuffix$fragmentSuffix';
  }

  @override
  String toString() {
    return href;
  }
}

/// UTF-8 that never throws: a bad sequence becomes U+FFFD, as browsers decode it.
class Utf8Lenient {
  const Utf8Lenient();

  /// The bytes as text, each malformed or cut-off sequence as one U+FFFD.
  String convert(List<int> bytes) {
    final buffer = StringBuffer();
    var index = 0;
    while (index < bytes.length) {
      final leadByte = bytes[index];
      int continuationCount, rune;
      if (leadByte < 0x80) {
        buffer.writeCharCode(leadByte);
        index++;
        continue;
      } else if (leadByte >= 0xC2 && leadByte <= 0xDF) {
        continuationCount = 1;
        rune = leadByte & 0x1F;
      } else if (leadByte >= 0xE0 && leadByte <= 0xEF) {
        continuationCount = 2;
        rune = leadByte & 0x0F;
      } else if (leadByte >= 0xF0 && leadByte <= 0xF4) {
        continuationCount = 3;
        rune = leadByte & 0x07;
      } else {
        buffer.writeCharCode(0xFFFD);
        index++;
        continue;
      }
      if (index + continuationCount >= bytes.length) {
        buffer.writeCharCode(0xFFFD);
        index++;
        continue;
      }
      var valid = true;
      for (var offset = 1; offset <= continuationCount; offset++) {
        final continuationByte = bytes[index + offset];
        if (continuationByte & 0xC0 != 0x80) {
          valid = false;
          break;
        }
        rune = (rune << 6) | (continuationByte & 0x3F);
      }
      if (!valid) {
        buffer.writeCharCode(0xFFFD);
        index++;
        continue;
      }
      buffer.writeCharCode(rune);
      index += continuationCount + 1;
    }
    return buffer.toString();
  }
}

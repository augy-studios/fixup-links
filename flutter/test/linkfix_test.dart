// The app's cleaner (lib/data/linkfix.dart) against the site's own (main-site/script.js), as
// tool/linkfix_expected.mjs recorded it: every list the same, and every link cleaned the same.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwufix/data/linkfix.dart';

void main() {
  final expected = jsonDecode(File('test/fixtures/linkfix_expected.json').readAsStringSync()) as Map<String, dynamic>;
  final lists = expected['lists'] as Map<String, dynamic>;

  test('the lists are script.js’s', () {
    expect(trackerPrefixes, lists['trackerPrefixes']);
    expect(universalTrackers.toSet(), (lists['universal'] as List).toSet());
    final platform = lists['platform'] as Map<String, dynamic>;
    expect(platformTrackers.keys.toList(), platform.keys.toList(), reason: 'the same hosts, in the same order');
    for (final e in platform.entries) {
      expect(platformTrackers[e.key], (e.value as List).toSet(), reason: e.key);
    }
    final patterns = lists['patterns'] as Map<String, dynamic>;
    expect(platformTrackerPatterns.keys.toSet(), patterns.keys.toSet());
    for (final e in patterns.entries) {
      expect(platformTrackerPatterns[e.key]!.pattern, e.value, reason: e.key);
    }
    expect(stripAllParamHosts, lists['stripAllHosts']);
    expect(stripAllParamPath, lists['stripAllPath']);
    expect(mastodonInstances, lists['mastodon']);
    expect(converterNames, lists['converters']);
  });

  for (final c in (expected['clean'] as List).cast<Map<String, dynamic>>()) {
    test('cleans ${c['input']}', () {
      if (c['error'] != null) {
        expect(() => cleanUrl(c['input'] as String), throwsA(isA<LinkFixError>().having((e) => e.message, 'message', c['error'])));
        return;
      }
      final r = cleanUrl(c['input'] as String);
      expect(r.cleaned, c['cleaned']);
      expect(r.platform, c['platform']);
      expect(r.wasConverted, c['wasConverted']);
      expect([for (final ch in r.changes) ch.toJson()], c['changes']);
    });
  }

  test('finds the link in text, as script.js does', () {
    for (final e in (expected['extract'] as List).cast<Map<String, dynamic>>()) {
      expect(extractUrlFromText(e['text'] as String), e['url'], reason: e['text'] as String);
    }
  });

  test('tells redirects apart, as script.js does', () {
    for (final e in (expected['redirects'] as List).cast<Map<String, dynamic>>()) {
      expect(isMeaningfulRedirect(e['a'] as String, e['b'] as String), e['meaningful'], reason: '${e['a']} → ${e['b']}');
      expect(urlsEquivalent(e['a'] as String, e['b'] as String), e['equivalent'], reason: '${e['a']} = ${e['b']}');
    }
  });

  test('puts the fixed link back in place of the highlighted one', () {
    expect(replaceLinkInText('see x.com/a/status/1 now', 'x.com/a/status/1', 'https://fixupx.com/i/status/1'), 'see https://fixupx.com/i/status/1 now');
    expect(replaceLinkInText('whatever', null, 'https://a.b/'), 'https://a.b/');
  });
}

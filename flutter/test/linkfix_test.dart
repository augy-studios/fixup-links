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
    for (final hostTrackers in platform.entries) {
      expect(platformTrackers[hostTrackers.key], (hostTrackers.value as List).toSet(), reason: hostTrackers.key);
    }
    final patterns = lists['patterns'] as Map<String, dynamic>;
    expect(platformTrackerPatterns.keys.toSet(), patterns.keys.toSet());
    for (final hostPattern in patterns.entries) {
      expect(platformTrackerPatterns[hostPattern.key]!.pattern, hostPattern.value, reason: hostPattern.key);
    }
    expect(stripAllParameterHosts, lists['stripAllHosts']);
    expect(stripAllParameterPath, lists['stripAllPath']);
    expect(mastodonInstances, lists['mastodon']);
    expect(converterNames, lists['converters']);
  });

  for (final testCase in (expected['clean'] as List).cast<Map<String, dynamic>>()) {
    test('cleans ${testCase['input']}', () {
      if (testCase['error'] != null) {
        final throwsTheError = throwsA(isA<LinkFixError>().having((error) {
          return error.message;
        }, 'message', testCase['error']));
        expect(() {
          return cleanUrl(testCase['input'] as String);
        }, throwsTheError);
        return;
      }
      final result = cleanUrl(testCase['input'] as String);
      expect(result.cleaned, testCase['cleaned']);
      expect(result.platform, testCase['platform']);
      expect(result.wasConverted, testCase['wasConverted']);
      final changes = <Map<String, Object?>>[];
      for (final change in result.changes) {
        changes.add(change.toJson());
      }
      expect(changes, testCase['changes']);
    });
  }

  test('finds the link in text, as script.js does', () {
    for (final testCase in (expected['extract'] as List).cast<Map<String, dynamic>>()) {
      expect(extractUrlFromText(testCase['text'] as String), testCase['url'], reason: testCase['text'] as String);
    }
  });

  test('tells redirects apart, as script.js does', () {
    for (final testCase in (expected['redirects'] as List).cast<Map<String, dynamic>>()) {
      final first = testCase['a'] as String;
      final second = testCase['b'] as String;
      expect(isMeaningfulRedirect(first, second), testCase['meaningful'], reason: '$first → $second');
      expect(urlsEquivalent(first, second), testCase['equivalent'], reason: '$first = $second');
    }
  });

  test('puts the fixed link back in place of the highlighted one', () {
    expect(replaceLinkInText('see x.com/a/status/1 now', 'x.com/a/status/1', 'https://fixupx.com/i/status/1'), 'see https://fixupx.com/i/status/1 now');
    expect(replaceLinkInText('whatever', null, 'https://a.b/'), 'https://a.b/');
  });
}

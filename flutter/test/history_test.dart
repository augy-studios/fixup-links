// The app's history merge (lib/data/history.dart) against the site's (main-site/js/history-merge.js),
// as tool/history_expected.mjs recorded it: sharing history between a phone, a computer and the
// website has to give the same history whichever end merges. Also the history's own functions.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwufix/data/history.dart';
import 'package:uwufix/data/store.dart';

List<Map<String, Object?>> _json(List<HistoryEntry> items) {
  final jsonItems = <Map<String, Object?>>[];
  for (final entry in items) {
    jsonItems.add(entry.toJson());
  }
  return jsonItems;
}

void main() {
  final expected = jsonDecode(File('test/fixtures/history_expected.json').readAsStringSync()) as Map<String, dynamic>;

  test('each entry from another device is checked as the site checks it', () {
    for (final testCase in (expected['sanitize'] as List).cast<Map<String, dynamic>>()) {
      expect(sanitizeEntry(testCase['input'])?.toJson(), testCase['output'], reason: '${testCase['input']}');
    }
  });

  for (final testCase in (expected['merge'] as List).cast<Map<String, dynamic>>()) {
    test('merges as the site does: ${testCase['name']}', () {
      final mine = <HistoryEntry>[];
      for (final value in testCase['mine'] as List) {
        mine.add(HistoryEntry.fromJson(value)!);
      }
      final merged = mergeHistory(mine, testCase['theirs'] as List);
      expect(_json(merged.items), testCase['items']);
      expect(merged.added, testCase['added']);
    });
  }

  test('a link cleaned again moves to the top, once, and the list stops at 100', () {
    Store.memory();
    final start = DateTime.utc(2026, 11, 14, 5);
    for (var index = 0; index < 105; index++) {
      History.add('https://a.b/$index?utm_source=x', 'https://a.b/$index', 'General', now: start.add(Duration(minutes: index)));
    }
    History.add('https://a.b/50?fbclid=1', 'https://a.b/50', 'General', now: start.add(const Duration(days: 1)));
    final list = History.load();
    expect(list.length, maximumHistoryEntries);
    expect(list.first.cleaned, 'https://a.b/50');
    var timesListed = 0;
    for (final entry in list) {
      if (entry.cleaned == 'https://a.b/50') {
        timesListed++;
      }
    }
    expect(timesListed, 1);
    expect(list.first.date, '2026-11-15T05:00:00.000Z', reason: 'as toISOString() writes it');
    History.remove(list.first.id);
    var stillListed = false;
    for (final entry in History.load()) {
      if (entry.cleaned == 'https://a.b/50') {
        stillListed = true;
      }
    }
    expect(stillListed, isFalse);
    History.update(History.load().first.id, title: 'A title');
    expect(History.load().first.title, 'A title');
    History.clear();
    expect(History.load(), isEmpty);
  });
}

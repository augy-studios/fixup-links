// The app's history merge (lib/data/history.dart) against the site's (main-site/js/history-merge.js),
// as tool/history_expected.mjs recorded it: sharing history between a phone, a computer and the
// website has to give the same history whichever end merges. Also the history's own functions.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uwufix/data/history.dart';
import 'package:uwufix/data/store.dart';

List<Map<String, Object?>> _json(List<HistoryEntry> items) => [for (final e in items) e.toJson()];

void main() {
  final expected = jsonDecode(File('test/fixtures/history_expected.json').readAsStringSync()) as Map<String, dynamic>;

  test('each entry from another device is checked as the site checks it', () {
    for (final c in (expected['sanitize'] as List).cast<Map<String, dynamic>>()) {
      expect(sanitizeEntry(c['input'])?.toJson(), c['output'], reason: '${c['input']}');
    }
  });

  for (final c in (expected['merge'] as List).cast<Map<String, dynamic>>()) {
    test('merges as the site does: ${c['name']}', () {
      final mine = [for (final v in c['mine'] as List) HistoryEntry.fromJson(v)!];
      final got = mergeHistory(mine, c['theirs'] as List);
      expect(_json(got.items), c['items']);
      expect(got.added, c['added']);
    });
  }

  test('a link cleaned again moves to the top, once, and the list stops at 100', () {
    Store.memory();
    final t = DateTime.utc(2026, 11, 14, 5);
    for (var i = 0; i < 105; i++) {
      History.add('https://a.b/$i?utm_source=x', 'https://a.b/$i', 'General', now: t.add(Duration(minutes: i)));
    }
    History.add('https://a.b/50?fbclid=1', 'https://a.b/50', 'General', now: t.add(const Duration(days: 1)));
    final list = History.load();
    expect(list.length, maxHistory);
    expect(list.first.cleaned, 'https://a.b/50');
    expect(list.where((e) => e.cleaned == 'https://a.b/50').length, 1);
    expect(list.first.date, '2026-11-15T05:00:00.000Z', reason: 'as toISOString() writes it');
    History.remove(list.first.id);
    expect(History.load().any((e) => e.cleaned == 'https://a.b/50'), isFalse);
    History.update(History.load().first.id, title: 'A title');
    expect(History.load().first.title, 'A title');
    History.clear();
    expect(History.load(), isEmpty);
  });
}

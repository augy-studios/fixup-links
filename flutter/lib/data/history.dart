// The history: every link cleaned, newest first, as the site keeps it (main-site/script.js's
// uwufix_history, at most 100), each { id, original, cleaned, platform, title, date }.
//
// And merging two of them, for sharing history between devices (lib/sync/, the site's
// js/sync.js): the same rules on every platform, checked against the site's by
// test/history_test.dart (tool/history_expected.mjs).
//   - Each entry from another device is checked first (sanitize): anything that isn't a link
//     cleaned to http(s), with a date, is dropped, and every field is cut to size.
//   - One entry per cleaned link: the newer one stays, its title filled from the other's if it
//     had none.
//   - Newest first, at most 100, and no two with the same id.
import 'package:flutter/foundation.dart';

import 'store.dart';

const historyKey = 'uwufix_history';
const maxHistory = 100;

class HistoryEntry {
  const HistoryEntry({required this.id, required this.original, required this.cleaned, required this.platform, this.title, required this.date});

  final int id;
  final String original;
  final String cleaned;
  final String platform;
  final String? title;
  final String date; // ISO 8601, as the site's new Date().toISOString()

  DateTime get when => DateTime.tryParse(date) ?? DateTime.fromMillisecondsSinceEpoch(0);

  HistoryEntry copyWith({int? id, String? cleaned, String? title}) =>
      HistoryEntry(id: id ?? this.id, original: original, cleaned: cleaned ?? this.cleaned, platform: platform, title: title ?? this.title, date: date);

  Map<String, Object?> toJson() => {'id': id, 'original': original, 'cleaned': cleaned, 'platform': platform, 'title': title, 'date': date};

  static HistoryEntry? fromJson(Object? v) {
    if (v is! Map) return null;
    final cleaned = v['cleaned'];
    final date = v['date'];
    if (cleaned is! String || date is! String) return null;
    final id = v['id'];
    return HistoryEntry(
      id: id is num ? id.toInt() : (DateTime.tryParse(date)?.millisecondsSinceEpoch ?? 0),
      original: v['original'] is String ? v['original'] as String : cleaned,
      cleaned: cleaned,
      platform: v['platform'] is String ? v['platform'] as String : 'General',
      title: v['title'] is String ? v['title'] as String : null,
      date: date,
    );
  }
}

/// script.js's history functions, with a notifier for the screens that show it.
class History {
  History._();

  /// Every change, for the count on the History button and the page.
  static final changed = ValueNotifier<int>(0);

  static List<HistoryEntry> load() {
    final out = <HistoryEntry>[];
    for (final v in Store.I.list(historyKey)) {
      final e = HistoryEntry.fromJson(v);
      if (e != null) out.add(e);
    }
    return out;
  }

  static void save(List<HistoryEntry> items) {
    Store.I.putJson(historyKey, [for (final e in items) e.toJson()]);
    changed.value++;
  }

  /// A link just cleaned, at the top; an earlier one with the same cleaned link goes.
  static HistoryEntry add(String original, String cleaned, String platform, {String? title, DateTime? now}) {
    final at = now ?? DateTime.now();
    final entry = HistoryEntry(id: at.millisecondsSinceEpoch, original: original, cleaned: cleaned, platform: platform, title: title, date: isoMs(at));
    var list = [entry, ...load().where((h) => h.cleaned != cleaned)];
    if (list.length > maxHistory) list = list.sublist(0, maxHistory);
    save(list);
    return entry;
  }

  static void remove(int id) => save([for (final h in load()) if (h.id != id) h]);

  static void clear() {
    Store.I.remove(historyKey);
    changed.value++;
  }

  static void update(int id, {String? title, String? cleaned}) {
    final list = load();
    final i = list.indexWhere((h) => h.id == id);
    if (i == -1) return;
    list[i] = list[i].copyWith(title: title, cleaned: cleaned);
    save(list);
  }
}

// ---------- merging, for sharing between devices ----------

/// A time as JavaScript's toISOString() writes it: UTC, to the millisecond.
String isoMs(DateTime t) => DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true).toIso8601String();

final _web = RegExp(r'^https?://', caseSensitive: false);

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

/// An entry from another device, as one to keep, or null for one to drop.
HistoryEntry? sanitizeEntry(Object? v) {
  if (v is! Map) return null;
  final cleaned = v['cleaned'];
  final date = v['date'];
  if (cleaned is! String || cleaned.length > 2048 || !_web.hasMatch(cleaned)) return null;
  if (date is! String || date.length > 40) return null;
  final when = DateTime.tryParse(date);
  if (when == null) return null;
  final original = v['original'];
  final platform = v['platform'];
  final title = v['title'];
  final id = v['id'];
  return HistoryEntry(
    id: id is num && id.isFinite && id == id.roundToDouble() ? id.toInt() : when.millisecondsSinceEpoch,
    original: original is String && original.isNotEmpty ? _cut(original, 4096) : cleaned,
    cleaned: cleaned,
    platform: platform is String && platform.isNotEmpty ? _cut(platform, 60) : 'General',
    title: title is String && title.isNotEmpty ? _cut(title, 300) : null,
    date: isoMs(when),
  );
}

/// What merging gave: the history to keep, and how many links in it are new to [mine].
typedef Merged = ({List<HistoryEntry> items, int added});

/// Two histories as one (see the top of this file). [theirs] is sanitized here.
Merged mergeHistory(List<HistoryEntry> mine, List<Object?> theirs) {
  final byLink = <String, HistoryEntry>{};
  for (final e in mine) {
    byLink.putIfAbsent(e.cleaned, () => e);
  }
  final known = byLink.keys.toSet();
  for (final raw in theirs) {
    final e = sanitizeEntry(raw);
    if (e == null) continue;
    final had = byLink[e.cleaned];
    if (had == null) {
      byLink[e.cleaned] = e;
    } else if (e.when.isAfter(had.when)) {
      byLink[e.cleaned] = e.title == null && had.title != null ? e.copyWith(title: had.title) : e;
    } else if (had.title == null && e.title != null) {
      byLink[e.cleaned] = had.copyWith(title: e.title);
    }
  }
  final all = byLink.values.toList()
    ..sort((a, b) {
      final d = b.when.compareTo(a.when);
      return d != 0 ? d : b.id.compareTo(a.id);
    });
  final kept = all.length > maxHistory ? all.sublist(0, maxHistory) : all;
  final ids = <int>{};
  final items = <HistoryEntry>[];
  for (final e in kept) {
    var id = e.id;
    while (ids.contains(id)) {
      id++;
    }
    ids.add(id);
    items.add(id == e.id ? e : e.copyWith(id: id));
  }
  return (items: items, added: items.where((e) => !known.contains(e.cleaned)).length);
}

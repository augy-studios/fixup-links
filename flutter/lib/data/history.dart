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
const maximumHistoryEntries = 100;

class HistoryEntry {
  const HistoryEntry({required this.id, required this.original, required this.cleaned, required this.platform, this.title, required this.date});

  final int id;
  final String original;
  final String cleaned;
  final String platform;
  final String? title;
  final String date; // ISO 8601, as the site's new Date().toISOString()

  DateTime get when {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    return parsed;
  }

  HistoryEntry copyWith({int? id, String? cleaned, String? title}) {
    var newId = this.id;
    if (id != null) {
      newId = id;
    }
    var newCleaned = this.cleaned;
    if (cleaned != null) {
      newCleaned = cleaned;
    }
    var newTitle = this.title;
    if (title != null) {
      newTitle = title;
    }
    return HistoryEntry(id: newId, original: original, cleaned: newCleaned, platform: platform, title: newTitle, date: date);
  }

  Map<String, Object?> toJson() {
    return {'id': id, 'original': original, 'cleaned': cleaned, 'platform': platform, 'title': title, 'date': date};
  }

  /// An entry as the app itself saved it, or null for one that isn't an entry at all. Missing
  /// fields get the same defaults the site gives them.
  static HistoryEntry? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final cleaned = value['cleaned'];
    final date = value['date'];
    if (cleaned is! String || date is! String) {
      return null;
    }
    final rawId = value['id'];
    int id;
    if (rawId is num) {
      id = rawId.toInt();
    } else {
      final parsedDate = DateTime.tryParse(date);
      if (parsedDate == null) {
        id = 0;
      } else {
        id = parsedDate.millisecondsSinceEpoch;
      }
    }
    String original;
    if (value['original'] is String) {
      original = value['original'] as String;
    } else {
      original = cleaned;
    }
    String platform;
    if (value['platform'] is String) {
      platform = value['platform'] as String;
    } else {
      platform = 'General';
    }
    String? title;
    if (value['title'] is String) {
      title = value['title'] as String;
    } else {
      title = null;
    }
    return HistoryEntry(
      id: id,
      original: original,
      cleaned: cleaned,
      platform: platform,
      title: title,
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
    final entries = <HistoryEntry>[];
    for (final value in Store.I.list(historyKey)) {
      final entry = HistoryEntry.fromJson(value);
      if (entry != null) {
        entries.add(entry);
      }
    }
    return entries;
  }

  static void save(List<HistoryEntry> items) {
    final jsonItems = <Map<String, Object?>>[];
    for (final entry in items) {
      jsonItems.add(entry.toJson());
    }
    Store.I.putJson(historyKey, jsonItems);
    changed.value++;
  }

  /// A link just cleaned, at the top; an earlier one with the same cleaned link goes.
  static HistoryEntry add(String original, String cleaned, String platform, {String? title, DateTime? now}) {
    var cleanedAt = DateTime.now();
    if (now != null) {
      cleanedAt = now;
    }
    final entry = HistoryEntry(
      id: cleanedAt.millisecondsSinceEpoch,
      original: original,
      cleaned: cleaned,
      platform: platform,
      title: title,
      date: isoMilliseconds(cleanedAt),
    );
    var list = <HistoryEntry>[entry];
    for (final earlier in load()) {
      if (earlier.cleaned != cleaned) {
        list.add(earlier);
      }
    }
    if (list.length > maximumHistoryEntries) {
      list = list.sublist(0, maximumHistoryEntries);
    }
    save(list);
    return entry;
  }

  static void remove(int id) {
    final kept = <HistoryEntry>[];
    for (final entry in load()) {
      if (entry.id != id) {
        kept.add(entry);
      }
    }
    save(kept);
  }

  static void clear() {
    Store.I.remove(historyKey);
    changed.value++;
  }

  static void update(int id, {String? title, String? cleaned}) {
    final list = load();
    final index = list.indexWhere((entry) {
      return entry.id == id;
    });
    if (index == -1) {
      return;
    }
    list[index] = list[index].copyWith(title: title, cleaned: cleaned);
    save(list);
  }
}

// ---------- merging, for sharing between devices ----------

/// A time as JavaScript's toISOString() writes it: UTC, to the millisecond.
String isoMilliseconds(DateTime time) {
  return DateTime.fromMillisecondsSinceEpoch(time.millisecondsSinceEpoch, isUtc: true).toIso8601String();
}

final _webLink = RegExp(r'^https?://', caseSensitive: false);

String _cut(String text, int maximumLength) {
  if (text.length > maximumLength) {
    return text.substring(0, maximumLength);
  }
  return text;
}

/// An entry from another device, as one to keep, or null for one to drop.
HistoryEntry? sanitizeEntry(Object? value) {
  if (value is! Map) {
    return null;
  }
  final cleaned = value['cleaned'];
  final date = value['date'];
  if (cleaned is! String || cleaned.length > 2048 || !_webLink.hasMatch(cleaned)) {
    return null;
  }
  if (date is! String || date.length > 40) {
    return null;
  }
  final when = DateTime.tryParse(date);
  if (when == null) {
    return null;
  }
  final original = value['original'];
  final platform = value['platform'];
  final title = value['title'];
  final rawId = value['id'];
  int id;
  if (rawId is num && rawId.isFinite && rawId == rawId.roundToDouble()) {
    id = rawId.toInt();
  } else {
    id = when.millisecondsSinceEpoch;
  }
  String keptOriginal;
  if (original is String && original.isNotEmpty) {
    keptOriginal = _cut(original, 4096);
  } else {
    keptOriginal = cleaned;
  }
  String keptPlatform;
  if (platform is String && platform.isNotEmpty) {
    keptPlatform = _cut(platform, 60);
  } else {
    keptPlatform = 'General';
  }
  String? keptTitle;
  if (title is String && title.isNotEmpty) {
    keptTitle = _cut(title, 300);
  } else {
    keptTitle = null;
  }
  return HistoryEntry(
    id: id,
    original: keptOriginal,
    cleaned: cleaned,
    platform: keptPlatform,
    title: keptTitle,
    date: isoMilliseconds(when),
  );
}

/// What merging gave: the history to keep, and how many links in it are new to [mine].
typedef Merged = ({List<HistoryEntry> items, int added});

/// Two histories as one (see the top of this file). [theirs] is sanitized here.
Merged mergeHistory(List<HistoryEntry> mine, List<Object?> theirs) {
  final byLink = <String, HistoryEntry>{};
  for (final entry in mine) {
    byLink.putIfAbsent(entry.cleaned, () {
      return entry;
    });
  }
  final known = byLink.keys.toSet();
  for (final raw in theirs) {
    final entry = sanitizeEntry(raw);
    if (entry == null) {
      continue;
    }
    final had = byLink[entry.cleaned];
    if (had == null) {
      byLink[entry.cleaned] = entry;
    } else if (entry.when.isAfter(had.when)) {
      if (entry.title == null && had.title != null) {
        byLink[entry.cleaned] = entry.copyWith(title: had.title);
      } else {
        byLink[entry.cleaned] = entry;
      }
    } else if (had.title == null && entry.title != null) {
      byLink[entry.cleaned] = had.copyWith(title: entry.title);
    }
  }
  final all = byLink.values.toList();
  all.sort((first, second) {
    final difference = second.when.compareTo(first.when);
    if (difference != 0) {
      return difference;
    }
    return second.id.compareTo(first.id);
  });
  List<HistoryEntry> kept;
  if (all.length > maximumHistoryEntries) {
    kept = all.sublist(0, maximumHistoryEntries);
  } else {
    kept = all;
  }
  final ids = <int>{};
  final items = <HistoryEntry>[];
  for (final entry in kept) {
    var id = entry.id;
    while (ids.contains(id)) {
      id++;
    }
    ids.add(id);
    if (id == entry.id) {
      items.add(entry);
    } else {
      items.add(entry.copyWith(id: id));
    }
  }
  var added = 0;
  for (final entry in items) {
    if (!known.contains(entry.cleaned)) {
      added++;
    }
  }
  return (items: items, added: added);
}

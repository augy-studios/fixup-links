// What the app keeps, under the same keys and in the same shapes the site keeps in localStorage
// (main-site/script.js's uwufix_history, js/theme.js's uwufix.mode and uwufix.colorTheme,
// js/tray.js's uwufix.trayOpen, js/tour.js's tour.welcome and tour.pages), so a feature reads
// what it always did and the WebView app's data (data/migrate.dart) needs no conversion: every
// value a string, JSON where the site's was.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Store {
  Store._(this._prefs);

  static Store? _instance;
  static Store get I => _instance ??= Store._(null);

  final SharedPreferences? _prefs;
  // Tests and screenshots: kept in memory only.
  final Map<String, String> _memory = {};
  final _changes = StreamController<String>.broadcast();

  /// Each key as it changes.
  Stream<String> get changes => _changes.stream;

  static Future<Store> open() async {
    final prefs = await SharedPreferences.getInstance();
    return _instance = Store._(prefs);
  }

  /// A store with these values and nothing written to the device.
  @visibleForTesting
  static Store memory([Map<String, String> values = const {}]) {
    final s = Store._(null);
    s._memory.addAll(values);
    return _instance = s;
  }

  // A prefix inside the platform's store, keeping the site's keys apart from plugins'.
  static const _prefix = 'ls.';

  String? get(String key) => _prefs == null ? _memory[key] : _prefs.getString('$_prefix$key');

  bool has(String key) => get(key) != null;

  void put(String key, String? value) {
    if (_prefs == null) {
      if (value == null) {
        _memory.remove(key);
      } else {
        _memory[key] = value;
      }
    } else if (value == null) {
      _prefs.remove('$_prefix$key');
    } else {
      _prefs.setString('$_prefix$key', value);
    }
    _changes.add(key);
  }

  void remove(String key) => put(key, null);

  /// The JSON at key, or fallback when there's none or it doesn't read.
  T json<T>(String key, T fallback) {
    final raw = get(key);
    if (raw == null) return fallback;
    try {
      final v = jsonDecode(raw);
      return v is T ? v : fallback;
    } catch (_) {
      return fallback;
    }
  }

  List<dynamic> list(String key) => json<List<dynamic>>(key, const []);

  void putJson(String key, Object? value) => put(key, value == null ? null : jsonEncode(value));

  /// Every key kept, for the migration.
  Iterable<String> get keys => _prefs == null
      ? _memory.keys
      : _prefs.getKeys().where((k) => k.startsWith(_prefix)).map((k) => k.substring(_prefix.length));
}

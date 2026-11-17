// What the app keeps, under the same keys and in the same shapes the site keeps in localStorage
// (main-site/script.js's uwufix_history, js/theme.js's uwufix.mode and uwufix.colorTheme,
// js/tray.js's uwufix.trayOpen, js/tour.js's tour.welcome and tour.pages), so a feature reads
// what it always did and the WebView app's data (data/migrate.dart) needs no conversion: every
// value a string, JSON where the site's was.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's key-value store: the platform's shared preferences on a device, or a map in memory
/// for tests and screenshots. Every value is a string, as in the site's localStorage.
class Store {
  Store._(this._preferences);

  static Store? _instance;
  static Store get I {
    final existing = _instance;
    if (existing != null) {
      return existing;
    }
    final created = Store._(null);
    _instance = created;
    return created;
  }

  final SharedPreferences? _preferences;
  // Tests and screenshots: kept in memory only.
  final Map<String, String> _memory = {};
  final _changes = StreamController<String>.broadcast();

  /// Each key as it changes.
  Stream<String> get changes {
    return _changes.stream;
  }

  static Future<Store> open() async {
    final preferences = await SharedPreferences.getInstance();
    final store = Store._(preferences);
    _instance = store;
    return store;
  }

  /// A store with these values and nothing written to the device.
  @visibleForTesting
  static Store memory([Map<String, String> values = const {}]) {
    final store = Store._(null);
    store._memory.addAll(values);
    _instance = store;
    return store;
  }

  // A prefix inside the platform's store, keeping the site's keys apart from plugins'.
  static const _prefix = 'ls.';

  String? get(String key) {
    final preferences = _preferences;
    if (preferences == null) {
      return _memory[key];
    }
    return preferences.getString('$_prefix$key');
  }

  bool has(String key) {
    return get(key) != null;
  }

  void put(String key, String? value) {
    final preferences = _preferences;
    if (preferences == null) {
      if (value == null) {
        _memory.remove(key);
      } else {
        _memory[key] = value;
      }
    } else if (value == null) {
      preferences.remove('$_prefix$key');
    } else {
      preferences.setString('$_prefix$key', value);
    }
    _changes.add(key);
  }

  void remove(String key) {
    put(key, null);
  }

  /// The JSON at key, or fallback when there's none or it doesn't read.
  T json<T>(String key, T fallback) {
    final raw = get(key);
    if (raw == null) {
      return fallback;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is T) {
        return decoded;
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  List<dynamic> list(String key) {
    return json<List<dynamic>>(key, const []);
  }

  void putJson(String key, Object? value) {
    if (value == null) {
      put(key, null);
    } else {
      put(key, jsonEncode(value));
    }
  }

  /// Every key kept, for the migration.
  Iterable<String> get keys {
    final preferences = _preferences;
    if (preferences == null) {
      return _memory.keys;
    }
    final storeKeys = <String>[];
    for (final key in preferences.getKeys()) {
      if (key.startsWith(_prefix)) {
        storeKeys.add(key.substring(_prefix.length));
      }
    }
    return storeKeys;
  }
}

// The app's native parts, from Dart: on Android, the Java plugins in android/app/src/main/java/
// org/uwuapps/fixup/ (FixupPlugin, PushNotificationsPlugin, MigratePlugin), over the bridge's
// method channel (bridge/Bridge.java); on the desktop, a Dart host answering the same calls
// (lib/desktop/host.dart). The same calls and events the site's page made of the app when it was
// a WebView (main-site/js/app-bridge.js), so the plugins' own notes still say what each does.
//
//   Native.call('Fixup', 'info')                 the plugin's answer, as a map (or null)
//   Native.on('Fixup', 'open', (data) {...})     its events, until .cancel()
//   Native.has('push')                           whether this build and device can (info's features)
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// A plugin call that failed: its message, and the code the plugin gave ("permission",
/// "cancelled", "unavailable", ...), with any data it added.
class NativeError implements Exception {
  NativeError(this.message, {this.code, this.data});
  final String message;
  final String? code;
  final Map<String, dynamic>? data;

  @override
  String toString() => message;
}

/// One listener on a plugin's event.
class NativeListener {
  NativeListener._(this._key, this._fn);
  final String _key;
  final void Function(Map<String, dynamic>) _fn;

  void cancel() => Native._remove(this);
}

/// What answers the bridge's calls when it isn't Android's Java: the desktop apps' host, and the
/// fakes in tests and screenshots.
abstract class NativeHost {
  Future<Map<String, dynamic>?> call(String plugin, String method, Map<String, dynamic> options);
  List<String> get features;
}

/// A Google Play build (build-apk.ps1 -Aab): Play updates it, so it has no updater of its own
/// (android/app/src/play/AndroidManifest.xml).
const playBuild = bool.fromEnvironment('FIXUP_PLAY');
const _notOnPlay = {'update', 'checkupdate'};

class Native {
  Native._();

  static const _channel = MethodChannel('org.uwuapps.fixup/bridge');
  static final Map<String, List<NativeListener>> _listeners = {};
  static bool _started = false;
  static Map<String, dynamic>? _info;

  /// Whether Android's native side is there: false on the desktop, in tests and screenshots.
  static bool available = true;

  /// The desktop's host (or a test's), standing in for Android's Java.
  static NativeHost? host;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    if (host != null) {
      available = false;
      _info = {'features': host!.features, ...?await host!.call('Fixup', 'info', const {})};
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return null;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      emit('${args['plugin']}', '${args['event']}', _decode(args['data'] as String?) ?? <String, dynamic>{});
      return null;
    });
    try {
      await _channel.invokeMethod('hello');
      _info = await call('Fixup', 'info');
    } on MissingPluginException {
      available = false;
    } catch (_) {
      _info = null;
    }
  }

  /// What this build and device can do, as FixupPlugin.info (or the desktop's host) lists it.
  static bool has(String feature) =>
      !(playBuild && _notOnPlay.contains(feature)) && ((_info?['features'] as List?) ?? const []).contains(feature);
  static Map<String, dynamic>? get info => _info;

  /// The app's version, such as "1.1.0", or null where there's no app (a test).
  static String? get version => _info?['version'] as String?;

  /// For tests and screenshots: the features a device has and the plugins' answers. Null
  /// [answer] puts things back.
  static void fake(List<String> features, Future<Map<String, dynamic>?> Function(String plugin, String method, Map<String, dynamic>? options)? answer) {
    _info = answer == null ? null : {'features': features};
    _fake = answer;
  }

  static Future<Map<String, dynamic>?> Function(String plugin, String method, Map<String, dynamic>? options)? _fake;

  /// One of a plugin's events, as if the device had sent it: the desktop's host sends its own
  /// this way, and tests theirs.
  static void emit(String plugin, String event, Map<String, dynamic> data) {
    final list = _listeners['$plugin.$event'];
    if (list == null || list.isEmpty) {
      // Kept for the first listener, as the Java side's retained events are.
      _held.putIfAbsent('$plugin.$event', () => []).add(data);
      return;
    }
    for (final l in List.of(list)) {
      try {
        l._fn(data);
      } catch (_) {
        // One listener's trouble isn't the others'.
      }
    }
  }

  static final Map<String, List<Map<String, dynamic>>> _held = {};

  static Future<Map<String, dynamic>?> call(String plugin, String method, [Map<String, dynamic>? options]) async {
    if (_fake != null) return _fake!(plugin, method, options);
    if (host != null) return host!.call(plugin, method, options ?? const {});
    if (!available) throw NativeError('Not in the app', code: 'unavailable');
    try {
      final json = await _channel.invokeMethod<String>('call', {
        'plugin': plugin,
        'method': method,
        'options': jsonEncode(options ?? const {}),
      });
      return _decode(json);
    } on PlatformException catch (e) {
      throw NativeError(e.message ?? 'Failed', code: e.code, data: _decode(e.details as String?));
    } on MissingPluginException {
      available = false;
      throw NativeError('Not in the app', code: 'unavailable');
    }
  }

  static NativeListener on(String plugin, String event, void Function(Map<String, dynamic>) fn) {
    final key = '$plugin.$event';
    final l = NativeListener._(key, fn);
    final list = _listeners.putIfAbsent(key, () => []);
    list.add(l);
    if (list.length == 1 && available && host == null) {
      _channel.invokeMethod('listen', {'plugin': plugin, 'event': event}).catchError((_) => null);
    }
    final held = _held.remove(key);
    if (held != null) {
      scheduleMicrotask(() {
        for (final d in held) {
          fn(d);
        }
      });
    }
    return l;
  }

  static void _remove(NativeListener l) {
    final list = _listeners[l._key];
    if (list == null || !list.remove(l) || list.isNotEmpty || !available || host != null) return;
    final parts = l._key.split('.');
    _channel.invokeMethod('unlisten', {'plugin': parts[0], 'event': parts[1]}).catchError((_) => null);
  }

  static Map<String, dynamic>? _decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final v = jsonDecode(json);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }
}

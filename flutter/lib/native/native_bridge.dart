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
  String toString() {
    return message;
  }
}

/// One listener on a plugin's event.
class NativeListener {
  NativeListener._(this._key, this._callback);
  final String _key;
  final void Function(Map<String, dynamic>) _callback;

  void cancel() {
    Native._remove(this);
  }
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

/// The bridge itself: calls to the plugins, their events, and what this build and device can do.
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

  /// Connects once: to the desktop's host if there is one, otherwise to Android's method channel,
  /// whose events are passed on to their listeners; then reads FixupPlugin's info.
  static Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    if (host != null) {
      available = false;
      final hostFeatures = host!.features;
      final hostInfo = await host!.call('Fixup', 'info', const {});
      _info = {'features': hostFeatures, ...?hostInfo};
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') {
        return null;
      }
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final decodedData = _decode(arguments['data'] as String?);
      Map<String, dynamic> eventData;
      if (decodedData != null) {
        eventData = decodedData;
      } else {
        eventData = <String, dynamic>{};
      }
      emit('${arguments['plugin']}', '${arguments['event']}', eventData);
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
  static bool has(String feature) {
    if (playBuild && _notOnPlay.contains(feature)) {
      return false;
    }
    final features = _info?['features'] as List?;
    if (features == null) {
      return false;
    }
    return features.contains(feature);
  }

  static Map<String, dynamic>? get info {
    return _info;
  }

  /// The app's version, such as "1.1.0", or null where there's no app (a test).
  static String? get version {
    return _info?['version'] as String?;
  }

  /// For tests and screenshots: the features a device has and the plugins' answers. Null
  /// [answer] puts things back.
  static void fake(List<String> features, Future<Map<String, dynamic>?> Function(String plugin, String method, Map<String, dynamic>? options)? answer) {
    if (answer == null) {
      _info = null;
    } else {
      _info = {'features': features};
    }
    _fake = answer;
  }

  static Future<Map<String, dynamic>?> Function(String plugin, String method, Map<String, dynamic>? options)? _fake;

  /// One of a plugin's events, as if the device had sent it: the desktop's host sends its own
  /// this way, and tests theirs.
  static void emit(String plugin, String event, Map<String, dynamic> data) {
    final list = _listeners['$plugin.$event'];
    if (list == null || list.isEmpty) {
      // Kept for the first listener, as the Java side's retained events are.
      _held.putIfAbsent('$plugin.$event', () {
        return [];
      }).add(data);
      return;
    }
    for (final listener in List.of(list)) {
      try {
        listener._callback(data);
      } catch (_) {
        // One listener's trouble isn't the others'.
      }
    }
  }

  static final Map<String, List<Map<String, dynamic>>> _held = {};

  /// One call to a plugin: answered by a test's fake, the desktop's host, or Android's Java over
  /// the method channel. A plugin's refusal comes back as a NativeError.
  static Future<Map<String, dynamic>?> call(String plugin, String method, [Map<String, dynamic>? options]) async {
    if (_fake != null) {
      return _fake!(plugin, method, options);
    }
    var givenOptions = const <String, dynamic>{};
    if (options != null) {
      givenOptions = options;
    }
    if (host != null) {
      return host!.call(plugin, method, givenOptions);
    }
    if (!available) {
      throw NativeError('Not in the app', code: 'unavailable');
    }
    try {
      final json = await _channel.invokeMethod<String>('call', {
        'plugin': plugin,
        'method': method,
        'options': jsonEncode(givenOptions),
      });
      return _decode(json);
    } on PlatformException catch (exception) {
      var message = 'Failed';
      if (exception.message != null) {
        message = exception.message!;
      }
      throw NativeError(message, code: exception.code, data: _decode(exception.details as String?));
    } on MissingPluginException {
      available = false;
      throw NativeError('Not in the app', code: 'unavailable');
    }
  }

  /// Listens to one of a plugin's events, until the listener is cancelled. The first listener
  /// asks Android's side to send the event, and gets any that came before it.
  static NativeListener on(String plugin, String event, void Function(Map<String, dynamic>) callback) {
    final key = '$plugin.$event';
    final listener = NativeListener._(key, callback);
    final list = _listeners.putIfAbsent(key, () {
      return [];
    });
    list.add(listener);
    if (list.length == 1 && available && host == null) {
      _channel.invokeMethod('listen', {'plugin': plugin, 'event': event}).catchError((_) {
        return null;
      });
    }
    final held = _held.remove(key);
    if (held != null) {
      scheduleMicrotask(() {
        for (final heldData in held) {
          callback(heldData);
        }
      });
    }
    return listener;
  }

  static void _remove(NativeListener listener) {
    final list = _listeners[listener._key];
    if (list == null || !list.remove(listener) || list.isNotEmpty || !available || host != null) {
      return;
    }
    final parts = listener._key.split('.');
    _channel.invokeMethod('unlisten', {'plugin': parts[0], 'event': parts[1]}).catchError((_) {
      return null;
    });
  }

  static Map<String, dynamic>? _decode(String? json) {
    if (json == null || json.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }
}

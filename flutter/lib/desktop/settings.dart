// The desktop apps' settings file (docs/desktop-features-spec.md §20): one JSON object, read and
// merged on every write so two parts of the app writing different keys never undo each other. A
// failed read is an empty object; a failed write is ignored.
//
//   %APPDATA%\uwuFix\settings.json, ~/Library/Application Support/uwuFix/settings.json,
//   ~/.config/uwuFix/settings.json
//
// Keys: bounds, maximized, trayHintShown (the window), loginChosen (start at sign-in), updateNotices
// (New versions of the app, missing means on), setupDone, pendingLook, useSystemAccent (Make it
// yours), widgets (the Fix a link widgets), linkHandoff (uwu:// links shared with sibling apps).
import 'dart:convert';
import 'dart:io';

/// The settings file: read whole, and merged key by key on every write.
class DesktopSettings {
  DesktopSettings._();

  /// The folder the settings file lives in, as each system keeps an app's settings.
  static String get folder {
    final environment = Platform.environment;
    if (Platform.isWindows) {
      String? base;
      if (environment['APPDATA'] != null) {
        base = environment['APPDATA'];
      } else {
        base = environment['USERPROFILE'];
      }
      return '$base\\uwuFix';
    }
    if (Platform.isMacOS) {
      return '${environment['HOME']}/Library/Application Support/uwuFix';
    }
    String config;
    if (environment['XDG_CONFIG_HOME'] != null) {
      config = environment['XDG_CONFIG_HOME']!;
    } else {
      config = '${environment['HOME']}/.config';
    }
    return '$config/uwuFix';
  }

  static File get _file {
    return File('$folder${Platform.pathSeparator}settings.json');
  }

  static Map<String, dynamic> read() {
    try {
      final decoded = jsonDecode(_file.readAsStringSync());
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  static Object? get(String key) {
    return read()[key];
  }

  static void set(String key, Object? value) {
    merge({key: value});
  }

  /// Writes [values] over what's in the file (null removes a key), through a temporary file
  /// renamed over it so a half-written file is never left behind.
  static void merge(Map<String, Object?> values) {
    try {
      final all = read();
      for (final entry in values.entries) {
        if (entry.value == null) {
          all.remove(entry.key);
        } else {
          all[entry.key] = entry.value;
        }
      }
      Directory(folder).createSync(recursive: true);
      final temporaryFile = File('${_file.path}.tmp');
      temporaryFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(all));
      temporaryFile.renameSync(_file.path);
    } catch (_) {
      // Kept for this run only.
    }
  }
}

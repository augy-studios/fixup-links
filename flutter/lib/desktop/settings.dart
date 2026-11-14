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

class DeskSettings {
  DeskSettings._();

  static String get folder {
    final env = Platform.environment;
    if (Platform.isWindows) return '${env['APPDATA'] ?? env['USERPROFILE']}\\uwuFix';
    if (Platform.isMacOS) return '${env['HOME']}/Library/Application Support/uwuFix';
    final config = env['XDG_CONFIG_HOME'] ?? '${env['HOME']}/.config';
    return '$config/uwuFix';
  }

  static File get _file => File('$folder${Platform.pathSeparator}settings.json');

  static Map<String, dynamic> read() {
    try {
      final v = jsonDecode(_file.readAsStringSync());
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  static Object? get(String key) => read()[key];

  static void set(String key, Object? value) => merge({key: value});

  static void merge(Map<String, Object?> values) {
    try {
      final all = read();
      for (final e in values.entries) {
        if (e.value == null) {
          all.remove(e.key);
        } else {
          all[e.key] = e.value;
        }
      }
      Directory(folder).createSync(recursive: true);
      final tmp = File('${_file.path}.tmp');
      tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(all));
      tmp.renameSync(_file.path);
    } catch (_) {
      // Kept for this run only.
    }
  }
}

// uwu:// links on the desktop (docs/desktop-features-spec.md §10). uwu://fix/<link> opens uwuFix
// with that link cleaned, as on Android (app/links.dart).
//
// A desktop OS gives a scheme to one app only, and uwu:// is shared by UwU Apps' apps (uwu://sgbus/
// is SG Bus Timings'). So each does the same handoff: at start, note which app holds the scheme now
// (if it isn't this one), then take it; a link for another app's host is passed to the app noted.
// Whichever started last holds the scheme and passes the others theirs. Links are passed as one
// argument, never through a shell.
//
//   Windows  HKCU\Software\Classes\uwu, registered at every start, so it survives updates and moves
//   Linux    the uwufix.desktop file's MimeType, made default with xdg-mime; the handler's Exec
//            line, %u filled in
//   macOS    the bundle's URL types (Info.plist); macOS hands each link to the app that asked last
//
// Kept: linkHandoff ({ command } on Windows, { desktop } on Linux).
import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

import '../app/links.dart';
import 'settings.dart';

const _hosts = {'fix', 'fixup'};

/// A uwu:// link for another app, not this one.
bool isOthersLink(String link) {
  final m = RegExp(r'^uwu://([^/?#]*)', caseSensitive: false).firstMatch(link);
  return m != null && !_hosts.contains(m.group(1)!.toLowerCase());
}

/// A link to open: this app's, or another's passed on. Whether it was this app's.
bool handleLink(String link) {
  if (isOthersLink(link)) {
    _passOn(link);
    return false;
  }
  return Links.open(link);
}

String get _exe => Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;

void registerLinkScheme() {
  try {
    if (Platform.isWindows) _registerWindows();
    if (Platform.isLinux) _registerLinux();
  } catch (_) {
    // Links just don't open the app; nothing else depends on it.
  }
}

void _registerWindows() {
  final ours = '"$_exe" "%1"';
  final key = Registry.openPath(RegistryHive.currentUser, path: r'Software\Classes', desiredAccessRights: AccessRights.allAccess);
  final uwu = key.createKey('uwu');
  final command = uwu.createKey(r'shell\open\command');
  final before = command.getStringValue('');
  if (before != null && before.isNotEmpty && before != ours && !before.contains(_exe)) {
    DeskSettings.set('linkHandoff', {'command': before});
  }
  uwu.createValue(const RegistryValue.string('', 'URL:uwu'));
  uwu.createValue(const RegistryValue.string('URL Protocol', ''));
  command.createValue(RegistryValue.string('', ours));
  command.close();
  uwu.close();
  key.close();
}

void _registerLinux() {
  final r = Process.runSync('xdg-mime', ['query', 'default', 'x-scheme-handler/uwu']);
  final now = '${r.stdout}'.trim();
  if (now.isNotEmpty && now != 'uwufix.desktop') DeskSettings.set('linkHandoff', {'desktop': now});
  Process.runSync('xdg-mime', ['default', 'uwufix.desktop', 'x-scheme-handler/uwu']);
}

void _passOn(String link) {
  final h = DeskSettings.get('linkHandoff');
  if (h is! Map) return;
  try {
    if (Platform.isWindows && h['command'] is String) {
      final parts = _split(h['command'] as String);
      if (parts.isEmpty) return;
      final args = [for (final a in parts.skip(1)) a == '%1' || a == '%L' ? link : a];
      if (!args.contains(link)) args.add(link);
      Process.start(parts.first, args, mode: ProcessStartMode.detached);
    } else if (Platform.isLinux && h['desktop'] is String) {
      final exec = _execOf(h['desktop'] as String);
      if (exec == null) return;
      final parts = _split(exec);
      final args = [for (final a in parts.skip(1)) if (!RegExp(r'^%[fFuUdDnNickvm]$').hasMatch(a) || a == '%u' || a == '%U') (a == '%u' || a == '%U') ? link : a];
      if (!args.contains(link)) args.add(link);
      Process.start(parts.first, args, mode: ProcessStartMode.detached);
    }
  } catch (_) {}
}

String? _execOf(String desktop) {
  final home = Platform.environment['HOME'] ?? '';
  final dirs = ['$home/.local/share/applications', '/usr/local/share/applications', '/usr/share/applications'];
  for (final d in dirs) {
    final f = File('$d/$desktop');
    if (!f.existsSync()) continue;
    for (final line in f.readAsLinesSync()) {
      if (line.startsWith('Exec=')) return line.substring(5);
    }
  }
  return null;
}

/// A command line split as Windows and desktop files quote it.
List<String> _split(String command) {
  final out = <String>[];
  final b = StringBuffer();
  var quoted = false;
  for (final ch in command.split('')) {
    if (ch == '"') {
      quoted = !quoted;
    } else if (ch == ' ' && !quoted) {
      if (b.isNotEmpty) out.add(b.toString());
      b.clear();
    } else {
      b.write(ch);
    }
  }
  if (b.isNotEmpty) out.add(b.toString());
  return out;
}

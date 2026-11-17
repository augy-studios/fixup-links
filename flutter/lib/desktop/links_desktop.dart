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
  final match = RegExp(r'^uwu://([^/?#]*)', caseSensitive: false).firstMatch(link);
  return match != null && !_hosts.contains(match.group(1)!.toLowerCase());
}

/// A link to open: this app's, or another's passed on. Whether it was this app's.
bool handleLink(String link) {
  if (isOthersLink(link)) {
    _passOn(link);
    return false;
  }
  return Links.open(link);
}

/// The program to register: the AppImage file when running from one, else the executable.
String get _executable {
  final appImage = Platform.environment['APPIMAGE'];
  if (appImage != null) {
    return appImage;
  }
  return Platform.resolvedExecutable;
}

void registerLinkScheme() {
  try {
    if (Platform.isWindows) {
      _registerWindows();
    }
    if (Platform.isLinux) {
      _registerLinux();
    }
  } catch (_) {
    // Links just don't open the app; nothing else depends on it.
  }
}

/// Points HKCU\Software\Classes\uwu at this app, noting the app that held it before.
void _registerWindows() {
  final ours = '"$_executable" "%1"';
  final key = Registry.openPath(RegistryHive.currentUser, path: r'Software\Classes', desiredAccessRights: AccessRights.allAccess);
  final uwu = key.createKey('uwu');
  final command = uwu.createKey(r'shell\open\command');
  final before = command.getStringValue('');
  if (before != null && before.isNotEmpty && before != ours && !before.contains(_executable)) {
    DesktopSettings.set('linkHandoff', {'command': before});
  }
  uwu.createValue(const RegistryValue.string('', 'URL:uwu'));
  uwu.createValue(const RegistryValue.string('URL Protocol', ''));
  command.createValue(RegistryValue.string('', ours));
  command.close();
  uwu.close();
  key.close();
}

void _registerLinux() {
  final result = Process.runSync('xdg-mime', ['query', 'default', 'x-scheme-handler/uwu']);
  final current = '${result.stdout}'.trim();
  if (current.isNotEmpty && current != 'uwufix.desktop') {
    DesktopSettings.set('linkHandoff', {'desktop': current});
  }
  Process.runSync('xdg-mime', ['default', 'uwufix.desktop', 'x-scheme-handler/uwu']);
}

/// Hands [link] to the app that held the scheme before this one, as its own command line would.
void _passOn(String link) {
  final handoff = DesktopSettings.get('linkHandoff');
  if (handoff is! Map) {
    return;
  }
  try {
    if (Platform.isWindows && handoff['command'] is String) {
      final parts = _split(handoff['command'] as String);
      if (parts.isEmpty) {
        return;
      }
      // The registry's %1 (or %L) is where the link goes.
      final arguments = <String>[];
      for (final argument in parts.skip(1)) {
        if (argument == '%1' || argument == '%L') {
          arguments.add(link);
        } else {
          arguments.add(argument);
        }
      }
      if (!arguments.contains(link)) {
        arguments.add(link);
      }
      Process.start(parts.first, arguments, mode: ProcessStartMode.detached);
    } else if (Platform.isLinux && handoff['desktop'] is String) {
      final commandLine = _commandLineOf(handoff['desktop'] as String);
      if (commandLine == null) {
        return;
      }
      final parts = _split(commandLine);
      // A desktop file's %u or %U is where the link goes; its other field codes are dropped.
      final arguments = <String>[];
      for (final argument in parts.skip(1)) {
        final isUrlCode = argument == '%u' || argument == '%U';
        final isFieldCode = RegExp(r'^%[fFuUdDnNickvm]$').hasMatch(argument);
        if (isUrlCode) {
          arguments.add(link);
        } else if (!isFieldCode) {
          arguments.add(argument);
        }
      }
      if (!arguments.contains(link)) {
        arguments.add(link);
      }
      Process.start(parts.first, arguments, mode: ProcessStartMode.detached);
    }
  } catch (_) {}
}

/// The command line (its Exec line) of the desktop file named [desktop], from wherever it's installed, or null.
String? _commandLineOf(String desktop) {
  String home;
  if (Platform.environment['HOME'] != null) {
    home = Platform.environment['HOME']!;
  } else {
    home = '';
  }
  final directories = ['$home/.local/share/applications', '/usr/local/share/applications', '/usr/share/applications'];
  for (final directory in directories) {
    final file = File('$directory/$desktop');
    if (!file.existsSync()) {
      continue;
    }
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('Exec=')) {
        return line.substring(5);
      }
    }
  }
  return null;
}

/// A command line split as Windows and desktop files quote it.
List<String> _split(String command) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (final character in command.split('')) {
    if (character == '"') {
      quoted = !quoted;
    } else if (character == ' ' && !quoted) {
      if (buffer.isNotEmpty) {
        parts.add(buffer.toString());
      }
      buffer.clear();
    } else {
      buffer.write(character);
    }
  }
  if (buffer.isNotEmpty) {
    parts.add(buffer.toString());
  }
  return parts;
}

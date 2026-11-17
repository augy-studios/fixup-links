// Updating itself on the desktop (docs/desktop-features-spec.md §3, flutter-desktop-app-spec.md
// §9): the newest release's update file for this platform, in the Electron updater's format,
// read from GitHub's "latest" download address, which always points at the newest release:
//
//   latest.yml (Windows' setup .exe), latest-mac.yml (the .zip for each Mac processor),
//   latest-linux.yml and latest-linux-arm64.yml (the AppImage)
//   { version, files: [{ url, sha512 (base64), size }], path, sha512, releaseDate }
//
// What each install can do with it:
//   Windows .exe   download the new setup .exe, check its SHA-512, run it silently (/S --updated
//                  --force-run), quit; it reopens the app. Told apart by its uninstaller beside it.
//   Linux AppImage download, check, write beside the running one, make it runnable, rename it over
//                  (atomic), start it, quit.
//   macOS          a writable bundle not on a disk image: download the .zip for this processor,
//                  check, unzip beside, and swap the bundle in once the app has quit.
//   anything else  (the .msi, .deb, .rpm, a Mac app on a disk image, a copy from source): only
//                  say there's a new version, with a link to the release.
//
// When: at launch (the update window, splash.dart, up to 10 s), 30 s after the main window, every
// hour, and 20 s after the computer wakes (a jump in the clock between the timer's ticks). Each
// check is a few kilobytes, from no rate-limited API.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../features/update/update_bar.dart';
import 'desktop.dart';
import 'notify.dart';
import 'settings.dart';

const releasesLatest =
    'https://github.com/augy-studios/fixup-links/releases/latest';
const _downloadBase = '$releasesLatest/download/';

/// One release's update file for this platform: its version, file name, checksum and size.
class UpdateFile {
  const UpdateFile(this.version, this.file, this.sha512, this.size);
  final String version;
  final String file; // a file name on the release
  final String sha512; // base64
  final int size;

  /// The Electron updater's YAML, or null if it isn't one. [want] picks a file among several
  /// (the Mac's .zip for this processor).
  static UpdateFile? parse(String text, {bool Function(String name)? want}) {
    try {
      final yaml = loadYaml(text);
      if (yaml is! Map) {
        return null;
      }
      final version = _text(yaml, 'version');
      if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(version)) {
        return null;
      }
      final files = yaml['files'] as List?;
      if (files != null) {
        for (final file in files) {
          if (file is! Map) {
            continue;
          }
          final url = _text(file, 'url');
          if (url.isEmpty || (want != null && !want(url))) {
            continue;
          }
          final size = (file['size'] as num?)?.toInt();
          int sizeInBytes;
          if (size == null) {
            sizeInBytes = 0;
          } else {
            sizeInBytes = size;
          }
          return UpdateFile(
            version,
            url,
            _text(file, 'sha512'),
            sizeInBytes,
          );
        }
      }
      final path = _text(yaml, 'path');
      if (path.isNotEmpty && (want == null || want(path))) {
        return UpdateFile(version, path, _text(yaml, 'sha512'), 0);
      }
    } catch (_) {}
    return null;
  }

  /// [map][key] as text, or '' when it's missing.
  static String _text(Map map, String key) {
    final value = map[key];
    if (value == null) {
      return '';
    }
    return '$value';
  }
}

/// How this copy was installed, and so what it can do with an update.
enum InstallKind { nsis, appImage, mac, other, source }

/// Finds, downloads and installs new versions of the desktop app, as this install allows.
class DesktopUpdater implements UpdateBackend {
  DesktopUpdater(this.running);
  final String running;

  UpdateFile? _found;
  File? _downloaded;
  Timer? _hourly;
  DateTime _lastTick = DateTime.now();

  /// How this copy was installed: the Windows installer's (its uninstaller beside it), an
  /// AppImage, a Mac bundle it can write over, or anything else.
  static InstallKind get kind {
    if (Desktop.fromSource) {
      return InstallKind.source;
    }
    final executable = File(Platform.resolvedExecutable);
    if (Platform.isWindows) {
      if (File('${executable.parent.path}\\Uninstall uwuFix.exe').existsSync()) {
        return InstallKind.nsis;
      }
      return InstallKind.other;
    }
    if (Platform.isLinux) {
      if (Platform.environment.containsKey('APPIMAGE')) {
        return InstallKind.appImage;
      }
      return InstallKind.other;
    }
    if (Platform.isMacOS) {
      final app = _macBundle;
      if (app == null ||
          app.path.startsWith('/Volumes/') ||
          app.path.contains('AppTranslocation')) {
        return InstallKind.other;
      }
      try {
        final probe = File('${app.parent.path}/.uwufix-write-test');
        probe.writeAsStringSync('');
        probe.deleteSync();
        return InstallKind.mac;
      } catch (_) {
        return InstallKind.other;
      }
    }
    return InstallKind.other;
  }

  static Directory? get _macBundle {
    final path = Platform.resolvedExecutable;
    final bundleEnd = path.indexOf('.app/');
    if (bundleEnd == -1) {
      return null;
    }
    return Directory(path.substring(0, bundleEnd + 4));
  }

  String get _yamlName {
    if (Platform.isWindows) {
      return 'latest.yml';
    }
    if (Platform.isMacOS) {
      return 'latest-mac.yml';
    }
    if (_arm) {
      return 'latest-linux-arm64.yml';
    }
    return 'latest-linux.yml';
  }

  static bool get _arm {
    final dartVersion = Platform.version.toLowerCase();
    return dartVersion.contains('arm64') || dartVersion.contains('aarch64');
  }

  bool _want(String name) {
    if (Platform.isMacOS) {
      String processorSuffix;
      if (_arm) {
        processorSuffix = '-mac-arm64';
      } else {
        processorSuffix = '-mac-x64';
      }
      return name.endsWith('.zip') && name.contains(processorSuffix);
    }
    if (Platform.isLinux) {
      return name.endsWith('.AppImage');
    }
    return name.endsWith('.exe');
  }

  @override
  bool get canInstall {
    return const {
      InstallKind.nsis,
      InstallKind.appImage,
      InstallKind.mac,
    }.contains(kind);
  }

  /// The newest version's update file, or null if this is it.
  Future<UpdateFile?> find({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (kind == InstallKind.source) {
      return null;
    }
    final response = await http
        .get(
          Uri.parse('$_downloadBase$_yamlName'),
          headers: {'user-agent': Desktop.userAgent},
        )
        .timeout(timeout);
    if (response.statusCode == 404) {
      return null; // no release with desktop files yet
    }
    if (response.statusCode != 200) {
      throw HttpException('GitHub replied ${response.statusCode}');
    }
    final file = UpdateFile.parse(response.body, want: _want);
    if (file == null || !AppUpdate.newer(file.version, running)) {
      return null;
    }
    _found = file;
    return file;
  }

  @override
  Future<({String version, String page})?> latest() async {
    final file = await find();
    if (file == null) {
      return null;
    }
    return (version: file.version, page: releasesLatest);
  }

  /// Downloads the update file, checking its SHA-512 as it comes, and on a Mac unpacks it; then
  /// says it's ready to install.
  @override
  Future<void> download(
    void Function(double? progress, String? detail) progress,
  ) async {
    UpdateFile? file = _found;
    if (file == null) {
      file = await find();
      if (file == null) {
        return;
      }
    }
    final directory = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}uwufix-update',
    );
    directory.createSync(recursive: true);
    final output = File('${directory.path}${Platform.pathSeparator}${file.file}');
    final request = http.Request('GET', Uri.parse('$_downloadBase${file.file}'));
    request.headers['user-agent'] = Desktop.userAgent;
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw HttpException('GitHub replied ${response.statusCode}');
    }
    int total;
    if (response.contentLength != null) {
      total = response.contentLength!;
    } else {
      total = file.size;
    }
    final sink = output.openWrite();
    final digest = _Sink();
    final hasher = sha512.startChunkedConversion(digest);
    var done = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      hasher.add(chunk);
      done += chunk.length;
      if (total > 0) {
        progress(done / total, '${_megabytes(done)} of ${_megabytes(total)}');
      } else {
        progress(null, _megabytes(done));
      }
    }
    await sink.close();
    hasher.close();
    if (file.sha512.isNotEmpty && base64.encode(digest.value!.bytes) != file.sha512) {
      output.deleteSync();
      throw const FormatException(
        'The download doesn’t match the file on GitHub.',
      );
    }
    if (Platform.isMacOS) {
      // Unpacked now, so quitting only has to swap it in.
      final unpacked = Directory('${directory.path}/unpacked');
      if (unpacked.existsSync()) {
        unpacked.deleteSync(recursive: true);
      }
      unpacked.createSync();
      final result = await Process.run('ditto', [
        '-x',
        '-k',
        output.path,
        unpacked.path,
      ]);
      if (result.exitCode != 0) {
        throw const FormatException('The update wouldn’t unpack.');
      }
    }
    _downloaded = output;
    _say(
      file.version,
      'ready',
      'uwuFix ${file.version} is ready',
      'Click to restart and update. Otherwise it updates the next time you quit.',
      'update',
    );
  }

  static String _megabytes(int bytes) {
    return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  }

  bool get ready {
    return _downloaded != null;
  }

  /// Installs the downloaded update as this install allows, then quits; [reopen] starts the new
  /// version once it's in place.
  @override
  Future<void> install({bool reopen = true}) async {
    final file = _downloaded;
    if (file == null) {
      return;
    }
    switch (kind) {
      case InstallKind.nsis:
        await Process.start(file.path, [
          '/S',
          '--updated',
          if (reopen) '--force-run',
        ], mode: ProcessStartMode.detached);
      case InstallKind.appImage:
        final target = Platform.environment['APPIMAGE']!;
        final next = File('$target.new');
        await file.copy(next.path);
        await Process.run('chmod', ['+x', next.path]);
        next.renameSync(target);
        if (reopen) {
          await Process.start(
            target,
            const [],
            mode: ProcessStartMode.detached,
          );
        }
      case InstallKind.mac:
        final app = _macBundle!;
        final unpacked = Directory('${file.parent.path}/unpacked');
        final newApp = unpacked.listSync().whereType<Directory>().firstWhere((directory) {
          return directory.path.endsWith('.app');
        });
        String reopenLine;
        if (reopen) {
          reopenLine = 'open "\$OLD"';
        } else {
          reopenLine = '';
        }
        // Waits for this process to end, swaps the bundles (keeping the old if the move fails),
        // clears the quarantine flag and reopens it.
        final script = File('${file.parent.path}/swap.sh');
        script.writeAsStringSync('''#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
OLD="${app.path}"
mv "\$OLD" "\$OLD.old" && if mv "${newApp.path}" "\$OLD"; then rm -rf "\$OLD.old"; else mv "\$OLD.old" "\$OLD"; fi
xattr -dr com.apple.quarantine "\$OLD" 2>/dev/null
$reopenLine
''');
        await Process.start('/bin/sh', [
          script.path,
        ], mode: ProcessStartMode.detached);
      default:
        return;
    }
    await Desktop.quit(installing: true);
  }

  /// Once per version, and only while New versions of the app is on (or when asked).
  void _say(
    String version,
    String what,
    String title,
    String body,
    String payload, {
    bool asked = false,
  }) {
    if (!asked && DesktopSettings.get('updateNotices') == false) {
      return;
    }
    final storedSaid = DesktopSettings.get('updateSaid') as Map?;
    Map<String, dynamic> said;
    if (storedSaid == null) {
      said = <String, dynamic>{};
    } else {
      said = Map<String, dynamic>.from(storedSaid);
    }
    final storedList = said[version] as List?;
    final list = <dynamic>[];
    if (storedList != null) {
      list.addAll(storedList);
    }
    if (!asked && list.contains(what)) {
      return;
    }
    DesktopSettings.set('updateSaid', {
      version: [...list, what],
    });
    DesktopNotify.show(title, body, payload: payload);
  }

  /// A check on its own, as the timers do it: downloads what this install can install, says what
  /// it can't.
  Future<void> background() async {
    try {
      final file = await find();
      if (file == null || ready) {
        return;
      }
      AppUpdate.I.version = file.version;
      AppUpdate.I.page = releasesLatest;
      if (!canInstall) {
        _say(
          file.version,
          'out',
          'uwuFix ${file.version} is out',
          'Click to download it from GitHub.',
          'release',
        );
        AppUpdate.I.check();
        return;
      }
      try {
        await AppUpdate.I.update();
      } catch (_) {
        _say(
          file.version,
          'failed',
          'Couldn’t download uwuFix ${file.version}',
          'It tries again within the hour, or click to download it from GitHub.',
          'release',
        );
      }
    } catch (_) {
      // Offline: says nothing unless asked.
    }
  }

  /// 30 s after the main window, every hour, and 20 s after the computer wakes.
  void schedule() {
    Timer(const Duration(seconds: 30), background);
    _lastTick = DateTime.now();
    var minutes = 0;
    _hourly = Timer.periodic(const Duration(minutes: 5), (_) {
      final now = DateTime.now();
      final slept = now.difference(_lastTick) > const Duration(minutes: 7);
      _lastTick = now;
      minutes += 5;
      if (slept) {
        minutes = 0;
        Timer(const Duration(seconds: 20), background);
      } else if (minutes >= 60) {
        minutes = 0;
        background();
      }
    });
  }

  void dispose() {
    _hourly?.cancel();
  }
}

/// Holds the SHA-512 digest once the download's hasher is closed.
class _Sink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

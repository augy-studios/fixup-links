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

const releasesLatest = 'https://github.com/augy-studios/fixup-links/releases/latest';
const _download = '$releasesLatest/download/';

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
      final y = loadYaml(text);
      if (y is! Map) return null;
      final version = '${y['version'] ?? ''}';
      if (!RegExp(r'^\d+(\.\d+)*$').hasMatch(version)) return null;
      final files = (y['files'] as List?) ?? const [];
      for (final f in files) {
        if (f is! Map) continue;
        final url = '${f['url'] ?? ''}';
        if (url.isEmpty || (want != null && !want(url))) continue;
        return UpdateFile(version, url, '${f['sha512'] ?? ''}', (f['size'] as num?)?.toInt() ?? 0);
      }
      final path = '${y['path'] ?? ''}';
      if (path.isNotEmpty && (want == null || want(path))) return UpdateFile(version, path, '${y['sha512'] ?? ''}', 0);
    } catch (_) {}
    return null;
  }
}

/// How this copy was installed, and so what it can do with an update.
enum InstallKind { nsis, appImage, mac, other, source }

class DesktopUpdater implements UpdateBackend {
  DesktopUpdater(this.running);
  final String running;

  UpdateFile? _found;
  File? _downloaded;
  Timer? _hourly;
  DateTime _lastTick = DateTime.now();

  static InstallKind get kind {
    if (Desktop.fromSource) return InstallKind.source;
    final exe = File(Platform.resolvedExecutable);
    if (Platform.isWindows) {
      return File('${exe.parent.path}\\Uninstall uwuFix.exe').existsSync() ? InstallKind.nsis : InstallKind.other;
    }
    if (Platform.isLinux) return Platform.environment.containsKey('APPIMAGE') ? InstallKind.appImage : InstallKind.other;
    if (Platform.isMacOS) {
      final app = _macBundle;
      if (app == null || app.path.startsWith('/Volumes/') || app.path.contains('AppTranslocation')) return InstallKind.other;
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
    final at = path.indexOf('.app/');
    return at == -1 ? null : Directory(path.substring(0, at + 4));
  }

  String get _ymlName {
    if (Platform.isWindows) return 'latest.yml';
    if (Platform.isMacOS) return 'latest-mac.yml';
    return _arm ? 'latest-linux-arm64.yml' : 'latest-linux.yml';
  }

  static bool get _arm {
    final v = Platform.version.toLowerCase();
    return v.contains('arm64') || v.contains('aarch64');
  }

  bool _want(String name) {
    if (Platform.isMacOS) return name.endsWith('.zip') && name.contains(_arm ? '-mac-arm64' : '-mac-x64');
    if (Platform.isLinux) return name.endsWith('.AppImage');
    return name.endsWith('.exe');
  }

  @override
  bool get canInstall => const {InstallKind.nsis, InstallKind.appImage, InstallKind.mac}.contains(kind);

  /// The newest version's update file, or null if this is it.
  Future<UpdateFile?> find({Duration timeout = const Duration(seconds: 15)}) async {
    if (kind == InstallKind.source) return null;
    final r = await http.get(Uri.parse('$_download$_ymlName'), headers: {'user-agent': Desktop.userAgent}).timeout(timeout);
    if (r.statusCode == 404) return null; // no release with desktop files yet
    if (r.statusCode != 200) throw HttpException('GitHub replied ${r.statusCode}');
    final f = UpdateFile.parse(r.body, want: _want);
    if (f == null || !AppUpdate.newer(f.version, running)) return null;
    return _found = f;
  }

  @override
  Future<({String version, String page})?> latest() async {
    final f = await find();
    return f == null ? null : (version: f.version, page: '$releasesLatest');
  }

  @override
  Future<void> download(void Function(double? progress, String? detail) progress) async {
    final f = _found ?? await find();
    if (f == null) return;
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}uwufix-update')..createSync(recursive: true);
    final out = File('${dir.path}${Platform.pathSeparator}${f.file}');
    final req = http.Request('GET', Uri.parse('$_download${f.file}'))..headers['user-agent'] = Desktop.userAgent;
    final res = await http.Client().send(req);
    if (res.statusCode != 200) throw HttpException('GitHub replied ${res.statusCode}');
    final total = res.contentLength ?? f.size;
    final sink = out.openWrite();
    final digest = _Sink();
    final hasher = sha512.startChunkedConversion(digest);
    var done = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      hasher.add(chunk);
      done += chunk.length;
      progress(total > 0 ? done / total : null, total > 0 ? '${_mb(done)} of ${_mb(total)}' : _mb(done));
    }
    await sink.close();
    hasher.close();
    if (f.sha512.isNotEmpty && base64.encode(digest.value!.bytes) != f.sha512) {
      out.deleteSync();
      throw const FormatException('The download doesn’t match the file on GitHub.');
    }
    if (Platform.isMacOS) {
      // Unpacked now, so quitting only has to swap it in.
      final unpacked = Directory('${dir.path}/unpacked');
      if (unpacked.existsSync()) unpacked.deleteSync(recursive: true);
      unpacked.createSync();
      final r = await Process.run('ditto', ['-x', '-k', out.path, unpacked.path]);
      if (r.exitCode != 0) throw const FormatException('The update wouldn’t unpack.');
    }
    _downloaded = out;
    _say(f.version, 'ready', 'uwuFix ${f.version} is ready', 'Click to restart and update. Otherwise it updates the next time you quit.', 'update');
  }

  static String _mb(int bytes) => '${(bytes / 1000000).toStringAsFixed(1)} MB';

  bool get ready => _downloaded != null;

  @override
  Future<void> install({bool reopen = true}) async {
    final file = _downloaded;
    if (file == null) return;
    switch (kind) {
      case InstallKind.nsis:
        await Process.start(file.path, ['/S', '--updated', if (reopen) '--force-run'], mode: ProcessStartMode.detached);
      case InstallKind.appImage:
        final target = Platform.environment['APPIMAGE']!;
        final next = File('$target.new');
        await file.copy(next.path);
        await Process.run('chmod', ['+x', next.path]);
        next.renameSync(target);
        if (reopen) await Process.start(target, const [], mode: ProcessStartMode.detached);
      case InstallKind.mac:
        final app = _macBundle!;
        final unpacked = Directory('${file.parent.path}/unpacked');
        final newApp = unpacked.listSync().whereType<Directory>().firstWhere((d) => d.path.endsWith('.app'));
        // Waits for this process to end, swaps the bundles (keeping the old if the move fails),
        // clears the quarantine flag and reopens it.
        final script = File('${file.parent.path}/swap.sh')
          ..writeAsStringSync('''#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
OLD="${app.path}"
mv "\$OLD" "\$OLD.old" && if mv "${newApp.path}" "\$OLD"; then rm -rf "\$OLD.old"; else mv "\$OLD.old" "\$OLD"; fi
xattr -dr com.apple.quarantine "\$OLD" 2>/dev/null
${reopen ? 'open "\$OLD"' : ''}
''');
        await Process.start('/bin/sh', [script.path], mode: ProcessStartMode.detached);
      default:
        return;
    }
    await Desktop.quit(installing: true);
  }

  /// Once per version, and only while New versions of the app is on (or when asked).
  void _say(String version, String what, String title, String body, String payload, {bool asked = false}) {
    if (!asked && DeskSettings.get('updateNotices') == false) return;
    final said = Map<String, dynamic>.from((DeskSettings.get('updateSaid') as Map?) ?? const {});
    final list = [...((said[version] as List?) ?? const [])];
    if (!asked && list.contains(what)) return;
    DeskSettings.set('updateSaid', {version: [...list, what]});
    DeskNotify.show(title, body, payload: payload);
  }

  /// A check on its own, as the timers do it: downloads what this install can install, says what
  /// it can't.
  Future<void> background() async {
    try {
      final f = await find();
      if (f == null || ready) return;
      AppUpdate.I.version = f.version;
      AppUpdate.I.page = releasesLatest;
      if (!canInstall) {
        _say(f.version, 'out', 'uwuFix ${f.version} is out', 'Click to download it from GitHub.', 'release');
        AppUpdate.I.check();
        return;
      }
      try {
        await AppUpdate.I.update();
      } catch (_) {
        _say(f.version, 'failed', 'Couldn’t download uwuFix ${f.version}', 'It tries again within the hour, or click to download it from GitHub.', 'release');
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

  void dispose() => _hourly?.cancel();
}

class _Sink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

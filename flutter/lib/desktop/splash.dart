// The update window at launch (docs/desktop-features-spec.md §2): a small frameless window, 300 x
// 360, draggable by anywhere, before the main window on every launch of an installed copy.
//
//   Checking for updates…   a wavy bar sweeping across, for up to 10 seconds
//   Downloading update      "Version 1.2.0", "31 of 85 MB", the wave filling up, and Later
//   Installing update…      then the app restarts as the new version
//   Starting…               nothing new, offline, too slow, or an install that can only be told:
//                           half a second, then the main window
//
// Later opens the app at once and leaves the download to finish in the background, ready for
// Restart (the update bar, the tray). Light or dark as the computer is, with its own colours, not
// the brand colour. UWUFIX_SPLASH_DEMO=1 runs it through every step with made-up numbers.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../features/update/update_bar.dart';
import '../widgets/wavy_progress.dart';
import 'updater.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.updater, required this.onDone});
  final DesktopUpdater updater;
  final Future<void> Function() onDone;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  String _step = 'checking';
  String? _version;
  double? _progress;
  String? _detail;
  bool _later = false;
  late final _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    Platform.environment['UWUFIX_SPLASH_DEMO'] == '1' ? _demo() : _run();
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  Future<void> _starting() async {
    if (!mounted) return;
    setState(() => _step = 'starting');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await widget.onDone();
  }

  Future<void> _run() async {
    UpdateFile? found;
    try {
      found = await widget.updater.find(timeout: const Duration(seconds: 10));
    } catch (_) {}
    if (found == null || !widget.updater.canInstall) {
      if (found != null) {
        AppUpdate.I.version = found.version;
        AppUpdate.I.page = releasesLatest;
        AppUpdate.I.state = 'available';
      }
      await _starting();
      return;
    }
    setState(() {
      _step = 'downloading';
      _version = found!.version;
      _progress = 0;
    });
    AppUpdate.I.version = found.version;
    final listener = () {
      if (!mounted) return;
      setState(() {
        _progress = AppUpdate.I.progress;
        _detail = AppUpdate.I.detail;
      });
    };
    AppUpdate.I.addListener(listener);
    await AppUpdate.I.update();
    AppUpdate.I.removeListener(listener);
    if (_later || !mounted) return; // the app's open: Restart's in the update bar and the tray
    if (widget.updater.ready) {
      setState(() => _step = 'installing');
      await widget.updater.install();
    } else {
      await _starting();
    }
  }

  Future<void> _demo() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    setState(() {
      _step = 'downloading';
      _version = '9.9.9';
    });
    for (var i = 0; i <= 85; i += 5) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted || _later) return;
      setState(() {
        _progress = i / 85;
        _detail = '$i of 85 MB';
      });
    }
    setState(() => _step = 'installing');
    await Future<void>.delayed(const Duration(seconds: 1));
    await _starting();
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final bg = dark ? const Color(0xFF1B1F1D) : const Color(0xFFF6F8F7);
    final ink = dark ? const Color(0xFFE8ECEA) : const Color(0xFF1A1F1C);
    final accent = dark ? const Color(0xFF9FD3B1) : const Color(0xFF2E6B47);
    final reduce = MediaQuery.of(context).disableAnimations;
    final (title, line) = switch (_step) {
      'checking' => ('Checking for updates…', null),
      'downloading' => ('Downloading update', _version == null ? null : 'Version $_version${_detail == null ? '' : '\n$_detail'}'),
      'installing' => ('Installing update…', null),
      _ => ('Starting…', null),
    };
    return Theme(
      data: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, colorSchemeSeed: accent, useMaterial3: true),
      child: Scaffold(
        backgroundColor: bg,
        body: DragToMoveArea(
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                AnimatedBuilder(
                  animation: _bob,
                  builder: (_, child) => Transform.translate(offset: Offset(0, reduce ? 0 : -6 * Curves.easeInOut.transform(_bob.value)), child: child),
                  child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.asset('assets/desktop/icon.png', width: 96, height: 96)),
                ),
                const SizedBox(height: 26),
                Semantics(liveRegion: true, child: Text(title, textAlign: TextAlign.center, style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w600))),
                if (line != null) ...[
                  const SizedBox(height: 6),
                  Text(line, textAlign: TextAlign.center, style: TextStyle(color: ink.withValues(alpha: 0.7), fontSize: 13)),
                ],
                const SizedBox(height: 18),
                if (_step == 'checking' || _step == 'downloading' || _step == 'installing')
                  WavyProgress(value: _step == 'downloading' ? _progress : null, color: accent, trackColor: accent.withValues(alpha: 0.2), semanticsLabel: title),
                if (_step == 'downloading') ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () {
                      _later = true;
                      widget.onDone();
                    },
                    child: const Text('Later'),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

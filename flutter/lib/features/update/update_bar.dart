// The app's update bar, at the top of the app, as the site's js/app-update.js had it in the WebView
// app, now in Material You with Material 3 Expressive's wavy progress (widgets/wavy_progress.dart):
//
//   checking      "Checking for updates…", a wave sweeping across (Check for app updates)
//   available     "Version 1.2.0 of uwuFix is out.", with Update and Not now
//   downloading   "Downloading 1.2.0", "31 of 85 MB", the wave filling up (the desktop apps)
//   ready         "1.2.0 is ready", with Restart (the desktop apps)
//   upToDate      "1.1.0 is the newest version." for a moment (Check for app updates)
//   failed        "Couldn't check for updates." for a moment
//
// On Android, Update opens the updates page (UpdateActivity): its own wavy bars while it checks and
// downloads, and every release's notes. On the desktop, the desktop's updater (lib/desktop/
// updater.dart) downloads it here. The Google Play build has neither: Play updates it.
//
// Looked up as the app opens, and again on coming back to it after six hours, as the app stays
// open for days. Not now lasts while the app is open.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/resolve.dart';
import '../../app/actions.dart';
import '../../native/native_bridge.dart';
import '../../theme/theme.dart';
import '../../widgets/wavy_progress.dart';

/// What the desktop's updater does in place of Android's updates page.
abstract class UpdateBackend {
  /// The newest version and its page, or null if this is it. Throws when it couldn't look.
  Future<({String version, String page})?> latest();

  /// Whether this install can update itself (an MSI or a .deb can only say there's one).
  bool get canInstall;

  /// Downloads it, saying how far it's got (0 to 1, or null).
  Future<void> download(void Function(double? progress, String? detail) progress);

  /// Restarts as the new version.
  Future<void> install();
}

class AppUpdate extends ChangeNotifier with WidgetsBindingObserver {
  AppUpdate._();
  static final AppUpdate I = AppUpdate._();

  static UpdateBackend? desktop;

  String state = 'idle';
  String? version;
  String? page;
  double? progress;
  String? detail;
  bool dismissed = false;
  int _checkedAt = 0;
  Timer? _hide;

  /// Whether this build updates itself at all: GitHub's Android APK and the desktop apps.
  static bool get supported => desktop != null || Native.has('update');

  /// Whether version a comes after b, number by number: 1.10.0 after 1.9.0. The same as
  /// main-site/api/_release.js's newer().
  static bool newer(String a, String b) {
    final x = a.split('.').map((n) => int.tryParse(n.replaceAll(RegExp(r'\D'), '')) ?? 0).toList();
    final y = b.split('.').map((n) => int.tryParse(n.replaceAll(RegExp(r'\D'), '')) ?? 0).toList();
    for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
      final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
      if (d != 0) return d > 0;
    }
    return false;
  }

  void start() {
    if (!supported) return;
    WidgetsBinding.instance.addObserver(this);
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && DateTime.now().millisecondsSinceEpoch - _checkedAt > 6 * 3600 * 1000) check();
  }

  void _set(String s, {Duration? hideAfter}) {
    state = s;
    _hide?.cancel();
    if (hideAfter != null) {
      _hide = Timer(hideAfter, () {
        state = 'idle';
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Looks for a newer version. [asked]: Check for app updates, which always says what it found.
  Future<void> check({bool asked = false}) async {
    if (!supported || state == 'checking' || state == 'downloading') return;
    _checkedAt = DateTime.now().millisecondsSinceEpoch;
    if (asked) {
      dismissed = false;
      _set('checking');
    }
    try {
      if (desktop != null) {
        final found = await desktop!.latest();
        if (found == null) {
          if (asked) _set('upToDate', hideAfter: const Duration(seconds: 4));
          return;
        }
        version = found.version;
        page = found.page;
        if (state != 'ready') _set('available');
        return;
      }
      final running = Native.version;
      final got = await Api.getJson('/api/app-release');
      final v = got?['version'] as String?;
      if (running != null && v != null && newer(v, running)) {
        version = v;
        page = got?['page'] as String?;
        _set('available');
      } else if (asked) {
        _set('upToDate', hideAfter: const Duration(seconds: 4));
      } else if (state == 'checking') {
        _set('idle');
      }
    } catch (_) {
      if (asked) _set('failed', hideAfter: const Duration(seconds: 4));
    }
  }

  /// Android's updates page: every release's notes, and the update, if there's one.
  /// A release's page, in the browser.
  static Future<void> openExternal(String url) => openLink(url);

  static Future<void> openPage({String? version, bool check = true}) async {
    try {
      await Native.call('Fixup', 'update', {'check': check, 'version': ?version});
    } catch (_) {}
  }

  Future<void> update() async {
    if (desktop == null) {
      await openPage(check: false);
      return;
    }
    if (!desktop!.canInstall) return;
    _set('downloading');
    progress = 0;
    try {
      await desktop!.download((p, d) {
        progress = p;
        detail = d;
        notifyListeners();
      });
      _set('ready');
    } catch (_) {
      _set('failed', hideAfter: const Duration(seconds: 6));
    }
  }

  void notNow() {
    dismissed = true;
    _set('idle');
  }
}

class AppUpdateBar extends StatelessWidget {
  const AppUpdateBar({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppUpdate.I,
        builder: (context, _) {
          final u = AppUpdate.I;
          if (u.state == 'idle' || (u.dismissed && u.state == 'available')) return const SizedBox.shrink();
          final scheme = Theme.of(context).colorScheme;
          final fx = context.fx;
          final (title, sub) = switch (u.state) {
            'checking' => ('Checking for updates…', null),
            'available' => ('Version ${u.version} of uwuFix is out.', AppUpdate.desktop != null && !AppUpdate.desktop!.canInstall ? 'Download it from GitHub.' : null),
            'downloading' => ('Downloading version ${u.version}', u.detail),
            'ready' => ('Version ${u.version} is ready', 'Restart to update. Otherwise it updates the next time you quit.'),
            'upToDate' => ('${Native.version ?? 'This'} is the newest version.', null),
            _ => ('Couldn’t check for updates.', 'Check you’re online, then try again.'),
          };
          final busy = u.state == 'checking' || u.state == 'downloading';
          return Semantics(
            container: true,
            liveRegion: true,
            label: 'App update',
            child: Material(
              color: fx.uwu ? fx.brandFill : scheme.secondaryContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Icon(
                        u.state == 'upToDate' ? Icons.check_circle_outline : u.state == 'failed' ? Icons.error_outline : Icons.system_update_alt,
                        color: fx.uwu ? fx.onBrand : scheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title, style: TextStyle(color: fx.uwu ? fx.onBrand : scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
                          if (sub != null) Text(sub, style: TextStyle(color: (fx.uwu ? fx.onBrand : scheme.onSecondaryContainer).withValues(alpha: 0.8), fontSize: 13)),
                        ]),
                      ),
                      if (u.state == 'available' && (AppUpdate.desktop == null || AppUpdate.desktop!.canInstall))
                        FilledButton(onPressed: u.update, child: const Text('Update')),
                      if (u.state == 'available' && AppUpdate.desktop != null && !AppUpdate.desktop!.canInstall && u.page != null)
                        FilledButton(onPressed: () => AppUpdate.openExternal(u.page!), child: const Text('Download')),
                      if (u.state == 'ready') FilledButton(onPressed: () => AppUpdate.desktop?.install(), child: const Text('Restart')),
                      if (u.state == 'available' || u.state == 'ready')
                        TextButton(onPressed: u.notNow, child: Text('Not now', style: TextStyle(color: fx.uwu ? fx.onBrand : scheme.onSecondaryContainer))),
                    ]),
                    if (busy) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: WavyProgress(value: u.state == 'downloading' ? u.progress : null, semanticsLabel: title),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

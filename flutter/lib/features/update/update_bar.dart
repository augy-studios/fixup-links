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

/// The app's update state, shared by the bar, the desktop's splash and its menus: whether a newer
/// version is out, and how far its download has got.
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
  Timer? _hideTimer;

  /// Whether this build updates itself at all: GitHub's Android APK and the desktop apps.
  static bool get supported {
    return desktop != null || Native.has('update');
  }

  /// The numbers in a version, with anything but digits dropped from each part: "v1.10.0" gives
  /// [1, 10, 0]. A part with no digits counts as 0.
  static List<int> _versionNumbers(String version) {
    final numbers = <int>[];
    for (final part in version.split('.')) {
      final number = int.tryParse(part.replaceAll(RegExp(r'\D'), ''));
      if (number == null) {
        numbers.add(0);
      } else {
        numbers.add(number);
      }
    }
    return numbers;
  }

  /// Whether version [candidate] comes after [current], number by number: 1.10.0 after 1.9.0.
  /// The same as main-site/api/_release.js's newer().
  static bool newer(String candidate, String current) {
    final candidateNumbers = _versionNumbers(candidate);
    final currentNumbers = _versionNumbers(current);
    int longest;
    if (candidateNumbers.length > currentNumbers.length) {
      longest = candidateNumbers.length;
    } else {
      longest = currentNumbers.length;
    }
    for (var index = 0; index < longest; index++) {
      var candidateNumber = 0;
      if (index < candidateNumbers.length) {
        candidateNumber = candidateNumbers[index];
      }
      var currentNumber = 0;
      if (index < currentNumbers.length) {
        currentNumber = currentNumbers[index];
      }
      final difference = candidateNumber - currentNumber;
      if (difference != 0) {
        return difference > 0;
      }
    }
    return false;
  }

  void start() {
    if (!supported) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sinceLastCheck = DateTime.now().millisecondsSinceEpoch - _checkedAt;
    if (state == AppLifecycleState.resumed && sinceLastCheck > 6 * 3600 * 1000) {
      check();
    }
  }

  /// Moves to [newState], and back to idle after [hideAfter] if it's given.
  void _changeState(String newState, {Duration? hideAfter}) {
    state = newState;
    _hideTimer?.cancel();
    if (hideAfter != null) {
      _hideTimer = Timer(hideAfter, () {
        state = 'idle';
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Looks for a newer version. [asked]: Check for app updates, which always says what it found.
  Future<void> check({bool asked = false}) async {
    if (!supported || state == 'checking' || state == 'downloading') {
      return;
    }
    _checkedAt = DateTime.now().millisecondsSinceEpoch;
    if (asked) {
      dismissed = false;
      _changeState('checking');
    }
    try {
      final desktopBackend = desktop;
      if (desktopBackend != null) {
        final found = await desktopBackend.latest();
        if (found == null) {
          if (asked) {
            _changeState('upToDate', hideAfter: const Duration(seconds: 4));
          }
          return;
        }
        version = found.version;
        page = found.page;
        if (state != 'ready') {
          _changeState('available');
        }
        return;
      }
      final running = Native.version;
      final release = await Api.getJson('/api/app-release');
      final latestVersion = release?['version'] as String?;
      if (running != null && latestVersion != null && newer(latestVersion, running)) {
        version = latestVersion;
        page = release?['page'] as String?;
        _changeState('available');
      } else if (asked) {
        _changeState('upToDate', hideAfter: const Duration(seconds: 4));
      } else if (state == 'checking') {
        _changeState('idle');
      }
    } catch (_) {
      if (asked) {
        _changeState('failed', hideAfter: const Duration(seconds: 4));
      }
    }
  }

  /// Android's updates page: every release's notes, and the update, if there's one.
  /// A release's page, in the browser.
  static Future<void> openExternal(String url) {
    return openLink(url);
  }

  static Future<void> openPage({String? version, bool check = true}) async {
    try {
      await Native.call('Fixup', 'update', {'check': check, 'version': ?version});
    } catch (_) {}
  }

  /// Updates: on Android, opens the updates page; on the desktop, downloads the new version here.
  Future<void> update() async {
    final desktopBackend = desktop;
    if (desktopBackend == null) {
      await openPage(check: false);
      return;
    }
    if (!desktopBackend.canInstall) {
      return;
    }
    _changeState('downloading');
    progress = 0;
    try {
      await desktopBackend.download((newProgress, newDetail) {
        progress = newProgress;
        detail = newDetail;
        notifyListeners();
      });
      _changeState('ready');
    } catch (_) {
      _changeState('failed', hideAfter: const Duration(seconds: 6));
    }
  }

  void notNow() {
    dismissed = true;
    _changeState('idle');
  }
}

/// The bar at the top of the app that says what the update is doing, with its buttons.
class AppUpdateBar extends StatelessWidget {
  const AppUpdateBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppUpdate.I,
      builder: (context, _) {
        return _buildBar(context, AppUpdate.I);
      },
    );
  }

  /// The bar for the update's current state, or nothing while there's nothing to say.
  Widget _buildBar(BuildContext context, AppUpdate update) {
    if (update.state == 'idle' || (update.dismissed && update.state == 'available')) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final palette = context.fx;
    final desktop = AppUpdate.desktop;

    String title;
    String? subtitle;
    switch (update.state) {
      case 'checking':
        title = 'Checking for updates…';
        subtitle = null;
      case 'available':
        title = 'Version ${update.version} of uwuFix is out.';
        if (desktop != null && !desktop.canInstall) {
          subtitle = 'Download it from GitHub.';
        } else {
          subtitle = null;
        }
      case 'downloading':
        title = 'Downloading version ${update.version}';
        subtitle = update.detail;
      case 'ready':
        title = 'Version ${update.version} is ready';
        subtitle = 'Restart to update. Otherwise it updates the next time you quit.';
      case 'upToDate':
        String runningVersion = 'This';
        final nativeVersion = Native.version;
        if (nativeVersion != null) {
          runningVersion = nativeVersion;
        }
        title = '$runningVersion is the newest version.';
        subtitle = null;
      default:
        title = 'Couldn’t check for updates.';
        subtitle = 'Check you’re online, then try again.';
    }
    final busy = update.state == 'checking' || update.state == 'downloading';

    Color barColor;
    Color textColor;
    if (palette.uwu) {
      barColor = palette.brandFill;
      textColor = palette.onBrand;
    } else {
      barColor = scheme.secondaryContainer;
      textColor = scheme.onSecondaryContainer;
    }

    IconData stateIcon;
    if (update.state == 'upToDate') {
      stateIcon = Icons.check_circle_outline;
    } else if (update.state == 'failed') {
      stateIcon = Icons.error_outline;
    } else {
      stateIcon = Icons.system_update_alt;
    }

    double? downloadProgress;
    if (update.state == 'downloading') {
      downloadProgress = update.progress;
    }

    final canInstallHere = desktop == null || desktop.canInstall;
    final onlyDownload = desktop != null && !desktop.canInstall;

    return Semantics(
      container: true,
      liveRegion: true,
      label: 'App update',
      child: Material(
        color: barColor,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Icon(stateIcon, color: textColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                    if (subtitle != null) Text(subtitle, style: TextStyle(color: textColor.withValues(alpha: 0.8), fontSize: 13)),
                  ]),
                ),
                if (update.state == 'available' && canInstallHere)
                  FilledButton(onPressed: update.update, child: const Text('Update')),
                if (update.state == 'available' && onlyDownload && update.page != null)
                  FilledButton(
                    onPressed: () {
                      AppUpdate.openExternal(update.page!);
                    },
                    child: const Text('Download'),
                  ),
                if (update.state == 'ready')
                  FilledButton(
                    onPressed: () {
                      AppUpdate.desktop?.install();
                    },
                    child: const Text('Restart'),
                  ),
                if (update.state == 'available' || update.state == 'ready')
                  TextButton(onPressed: update.notNow, child: Text('Not now', style: TextStyle(color: textColor))),
              ]),
              if (busy) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: WavyProgress(value: downloadProgress, semanticsLabel: title),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

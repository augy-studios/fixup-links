// uwuFix for Windows, macOS and Linux (1.1.0): the same Flutter app as Android's, with the
// desktop's own layer around it (docs/desktop-features-spec.md lists each feature, and
// flutter-desktop-app-spec.md how):
//
// - the update window at launch, and updating itself (splash.dart, updater.dart);
// - Make it yours, the first window, and from the tray's menu after that (welcome.dart);
// - a tray icon (the menu bar on macOS): closing the window keeps the app there (tray.dart);
// - its own title bar with back, forward, reload, the command bar, copy link, screenshots and the
//   window's buttons, a navigation rail, and History beside the cleaner on wide windows
//   (chrome.dart, screenshot.dart);
// - starting at sign-in, one copy at a time, uwu://fix links shared with UwU Apps' other apps
//   (links_desktop.dart), the Jump List and the Dock's menu (the runners);
// - Fix a link widgets on the desktop, each a small window of its own (widgets_window.dart);
// - new versions told by notification (notify.dart).
//
// What doesn't fit uwuFix is left out: it has no live item to count down in the tray, no map and
// no location, and no earlier desktop app to take over from.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../api/resolve.dart';
import '../app/app.dart';
import '../app/links.dart';
import '../app/nav.dart';
import '../data/store.dart';
import '../features/tour/tour.dart';
import '../features/update/update_bar.dart';
import '../native/native_bridge.dart';
import '../theme/theme.dart';
import 'chrome.dart';
import 'host.dart';
import 'links_desktop.dart';
import 'notify.dart';
import 'settings.dart';
import 'splash.dart';
import 'tray.dart';
import 'updater.dart';
import 'welcome.dart';
import 'widgets_window.dart';

class Desktop {
  Desktop._();

  static const name = 'uwuFix';
  static const appId = 'org.uwuapps.fixup';
  static String version = '';
  static String get userAgent => 'uwuFixDesktop/$version (+$site)';

  static bool get mac => Platform.isMacOS;
  static bool get windows => Platform.isWindows;
  static bool get linux => Platform.isLinux;

  /// Running from `flutter run` or straight from the build folder, not an installed copy: nothing
  /// is registered with the system then (start at sign-in, the uwu:// scheme), and nothing updates.
  static bool get fromSource {
    if (!kReleaseMode) return true;
    final sep = Platform.pathSeparator;
    return Platform.resolvedExecutable.contains('${sep}build$sep') && !Platform.environment.containsKey('APPIMAGE');
  }

  /// Quitting for real: closing the window then lets it go.
  static bool quitting = false;

  static DesktopUpdater? updater;

  static const channel = MethodChannel('org.uwuapps.fixup/desktop');

  static const minSize = Size(360, 520);
  static const defaultSize = Size(1120, 760);

  static Future<void> show() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.focus();
  }

  static Future<void> hide() async {
    await keepBounds();
    await windowManager.hide();
    if (DeskSettings.get('trayHintShown') != true) {
      DeskSettings.set('trayHintShown', true);
      DeskNotify.show(
        'uwuFix is still running',
        mac ? 'It stays in the menu bar. Quit it from the menu bar icon, or with ⌘Q.' : 'It stays in the tray, ready for the next link. Quit it from the tray icon.',
      );
    }
  }

  static Future<void> toggle() async {
    if (await windowManager.isVisible() && await windowManager.isFocused()) {
      await hide();
    } else {
      await show();
    }
  }

  /// Quits for real. An update that's downloaded installs now, without reopening.
  static Future<void> quit({bool installing = false}) async {
    quitting = true;
    await keepBounds();
    if (!installing && updater?.ready == true) {
      await updater!.install(reopen: false);
      return;
    }
    await Tray.dispose();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
    exit(0);
  }

  /// The main window's un-maximised size and place, and whether it was maximised.
  static Future<void> keepBounds() async {
    try {
      final max = await windowManager.isMaximized();
      final full = await windowManager.isFullScreen();
      final m = <String, Object?>{'maximized': max};
      if (!max && !full) {
        final b = await windowManager.getBounds();
        m['bounds'] = {'x': b.left, 'y': b.top, 'width': b.width, 'height': b.height};
      }
      DeskSettings.merge(m);
    } catch (_) {}
  }

  /// A link the app was opened with, or that a second copy passed on.
  static void openLink(String link) {
    if (!handleLink(link)) return;
    show();
  }
}

/// Where the app starts on the desktop: a widget's window, or the app itself.
Future<void> desktopMain(List<String> args) async {
  // desktop_multi_window starts each extra window as `main(['multi_window', id, json])`.
  if (args.isNotEmpty && args.first == 'multi_window') {
    final id = int.tryParse(args.length > 1 ? args[1] : '') ?? 0;
    final extra = args.length > 2 && args[2].isNotEmpty ? Map<String, dynamic>.from(jsonDecode(args[2]) as Map) : <String, dynamic>{};
    await runWidgetWindow(id, extra);
    return;
  }

  await Store.open();
  final info = await PackageInfo.fromPlatform();
  Desktop.version = info.version;
  Api.userAgent = Desktop.userAgent;
  Native.host = DesktopHost(info.version);
  await Native.start();
  await AppLook.I.readDevice();
  await windowManager.ensureInitialized();
  await DeskNotify.init(shortcut: !Desktop.fromSource);
  if (!Desktop.fromSource) registerLinkScheme();
  await _startAtSignIn();

  final updater = Desktop.updater = DesktopUpdater(info.version);
  AppUpdate.desktop = updater;

  // Links from a second copy, the Dock, the Jump List and macOS's URL events (the runners).
  Desktop.channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'open':
        final a = call.arguments;
        final links = a is List ? a.map((e) => '$e') : ['$a'];
        for (final l in links) {
          if (l.startsWith('uwu:') || l.startsWith('http')) Desktop.openLink(l);
        }
        if (links.every((l) => !l.startsWith('uwu:') && !l.startsWith('http'))) await Desktop.show();
      case 'activate':
        await Desktop.show();
      case 'task':
        await Desktop.show();
        runTask('${call.arguments}');
    }
    return null;
  });
  DeskNotify.onClick = (payload) async {
    await Desktop.show();
    switch (payload) {
      case 'update':
        if (updater.ready) await updater.install();
      case 'release':
        await Native.call('Fixup', 'open', {'url': releasesLatest}).catchError((_) => null);
      default:
        if (payload != null && payload.startsWith('file:')) {
          await revealFile(payload.substring(5));
        } else if (payload != null && payload.isNotEmpty) {
          handleLink(payload);
        }
    }
  };

  final launchLinks = args.where((a) => a.startsWith('uwu:') || a.startsWith('http')).toList();
  // A link for one of UwU Apps' other apps, which only started this copy to pass it on.
  if (launchLinks.isNotEmpty && launchLinks.every(isOthersLink)) {
    for (final l in launchLinks) {
      handleLink(l);
    }
    exit(0);
  }
  // A Jump List task (Windows) or Dock item (macOS) that started the app.
  final task = args.where((a) => a.startsWith('--task=')).map((a) => a.substring(7)).firstOrNull;
  runApp(DesktopRoot(launchLinks: launchLinks, launchTask: task));
}

Future<void> _startAtSignIn() async {
  try {
    final appImage = Platform.environment['APPIMAGE'];
    launchAtStartup.setup(appName: Desktop.name, appPath: appImage ?? Platform.resolvedExecutable, packageName: Desktop.appId);
    // On from the first run of an installed copy; the person's choice sticks once made.
    if (!Desktop.fromSource && DeskSettings.get('loginChosen') != true && !await launchAtStartup.isEnabled()) {
      await launchAtStartup.enable();
    }
  } catch (_) {}
}

Future<bool> startsAtSignIn() async {
  try {
    return await launchAtStartup.isEnabled();
  } catch (_) {
    return false;
  }
}

Future<void> setStartAtSignIn(bool on) async {
  DeskSettings.set('loginChosen', true);
  try {
    on ? await launchAtStartup.enable() : await launchAtStartup.disable();
  } catch (_) {}
}

/// Shows a file in its folder: Explorer, Finder, or the file manager.
Future<void> revealFile(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,', path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', path]);
    } else {
      await Process.start('xdg-open', [File(path).parent.path]);
    }
  } catch (_) {}
}

/// A Jump List task, the Dock menu, or the tray: what it asks for.
void runTask(String id) {
  switch (id) {
    case 'paste':
      fixCopied();
    case 'history':
      AppNav.showPage('history');
    case 'sync':
      AppNav.showPage('sync');
    case 'widget':
      openWidgetWindow();
    case 'welcome':
      DesktopRoot.state?.showWelcome();
  }
}

/// The phases of a launch: the update window, then Make it yours the first time, then the app.
class DesktopRoot extends StatefulWidget {
  const DesktopRoot({super.key, this.launchLinks = const [], this.launchTask});
  final List<String> launchLinks;
  final String? launchTask;

  static DesktopRootState? state;

  @override
  State<DesktopRoot> createState() => DesktopRootState();
}

class DesktopRootState extends State<DesktopRoot> with WindowListener {
  String _phase = 'splash';
  Timer? _boundsTimer;

  @override
  void initState() {
    super.initState();
    DesktopRoot.state = this;
    windowManager.addListener(this);
    _splashWindow();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // ---------- the windows of a launch ----------

  Future<void> _splashWindow() async {
    await windowManager.setPreventClose(true);
    await windowManager.setTitle(Desktop.name);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setResizable(false);
    await windowManager.setMinimumSize(const Size(300, 360));
    await windowManager.setSize(const Size(300, 360));
    await windowManager.center();
    // Not when it's been started at sign-in quietly? It always shows: the spec's update window
    // opens on every launch of an installed copy.
    await windowManager.show();
  }

  /// The update window said what it found: Make it yours the first time, then the main window.
  Future<void> splashDone() async {
    if (DeskSettings.get('setupDone') != true) {
      await showWelcome();
      return;
    }
    await _mainWindow();
  }

  Future<void> showWelcome() async {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: Desktop.mac);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(620, 560));
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
    await windowManager.setSize(const Size(940, 660));
    await windowManager.center();
    setState(() => _phase = 'welcome');
    await windowManager.show();
  }

  /// Make it yours closed, either way: seen, and on to the app.
  Future<void> welcomeDone() async {
    DeskSettings.set('setupDone', true);
    await _mainWindow();
  }

  Future<void> _mainWindow() async {
    if (_phase == 'main') {
      await Desktop.show();
      return;
    }
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: Desktop.mac);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(Desktop.minSize);
    final s = DeskSettings.read();
    final b = s['bounds'];
    if (b is Map && await _onScreen(b)) {
      await windowManager.setBounds(Rect.fromLTWH((b['x'] as num).toDouble(), (b['y'] as num).toDouble(), (b['width'] as num).toDouble(), (b['height'] as num).toDouble()));
    } else {
      await windowManager.setSize(Desktop.defaultSize);
      await windowManager.center();
    }
    setState(() => _phase = 'main');
    // Maximised unless it was last closed un-maximised.
    if (s['maximized'] != false) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
    await Tray.init();
    Desktop.updater?.schedule();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final l in widget.launchLinks) {
        handleLink(l);
      }
      if (DeskNotify.launchPayload != null) DeskNotify.onClick(DeskNotify.launchPayload);
      if (widget.launchTask != null) runTask(widget.launchTask!);
      reopenWidgetWindows();
      Timer(const Duration(milliseconds: 900), () => Tours.init(openedByLink: widget.launchLinks.isNotEmpty || widget.launchTask != null));
    });
  }

  // A kept place is used only if it's still on a screen (a monitor unplugged since).
  Future<bool> _onScreen(Map b) async {
    final x = (b['x'] as num?)?.toDouble(), y = (b['y'] as num?)?.toDouble();
    final w = (b['width'] as num?)?.toDouble(), h = (b['height'] as num?)?.toDouble();
    if (x == null || y == null || w == null || h == null || w < 200 || h < 200) return false;
    return x > -w + 80 && y > -20 && x < 10000 && y < 10000;
  }

  // ---------- the window's events ----------

  @override
  void onWindowClose() async {
    if (Desktop.quitting) return;
    if (_phase == 'welcome') {
      // Closing Make it yours changes nothing, but still counts as having seen it.
      await welcomeDone();
      return;
    }
    if (_phase == 'splash') return;
    await Desktop.hide();
  }

  void _kept() {
    if (_phase != 'main') return;
    _boundsTimer?.cancel();
    _boundsTimer = Timer(const Duration(milliseconds: 500), Desktop.keepBounds);
  }

  @override
  void onWindowMoved() => _kept();
  @override
  void onWindowResized() => _kept();
  @override
  void onWindowMaximize() => _kept();
  @override
  void onWindowUnmaximize() => _kept();

  @override
  Widget build(BuildContext context) => switch (_phase) {
        'splash' => UwuFixApp(home: SplashScreen(updater: Desktop.updater!, onDone: splashDone)),
        'welcome' => UwuFixApp(home: WelcomeScreen(onDone: welcomeDone)),
        _ => const UwuFixApp(desktopShell: DesktopShell()),
      };
}

/// What's copied, cleaned: the tray's and the Jump List's Fix copied link.
Future<void> fixCopied() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text?.trim() ?? '';
  AppNav.showPage('home');
  if (text.isEmpty) {
    AppNav.say('Nothing’s copied. Paste or type a link to fix it.');
    return;
  }
  Links.open(text);
}

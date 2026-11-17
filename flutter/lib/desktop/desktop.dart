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
// - new versions told by notification (notify.dart);
// - the system's backdrop behind the window in the desktop's glass look: Mica, the vibrancy, the
//   compositor's blur (backdrop.dart).
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
import 'backdrop.dart';
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

/// The desktop app's own state and window actions: show, hide, quit, and where the window was.
class Desktop {
  Desktop._();

  static const name = 'uwuFix';
  static const appId = 'org.uwuapps.fixup';
  static String version = '';
  static String get userAgent {
    return 'uwuFixDesktop/$version (+$site)';
  }

  static bool get mac {
    return Platform.isMacOS;
  }

  static bool get windows {
    return Platform.isWindows;
  }

  static bool get linux {
    return Platform.isLinux;
  }

  /// Running from `flutter run` or straight from the build folder, not an installed copy: nothing
  /// is registered with the system then (start at sign-in, the uwu:// scheme), and nothing updates.
  static bool get fromSource {
    if (!kReleaseMode) {
      return true;
    }
    final separator = Platform.pathSeparator;
    return Platform.resolvedExecutable.contains('${separator}build$separator') && !Platform.environment.containsKey('APPIMAGE');
  }

  /// Quitting for real: closing the window then lets it go.
  static bool quitting = false;

  static DesktopUpdater? updater;

  static const channel = MethodChannel('org.uwuapps.fixup/desktop');

  static const minimumSize = Size(360, 520);
  static const defaultSize = Size(1120, 760);

  static Future<void> show() async {
    await windowManager.show();
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.focus();
  }

  /// Hides the window to the tray, saying so by notification the first time.
  static Future<void> hide() async {
    await keepBounds();
    await windowManager.hide();
    if (DesktopSettings.get('trayHintShown') != true) {
      DesktopSettings.set('trayHintShown', true);
      String body;
      if (mac) {
        body = 'It stays in the menu bar. Quit it from the menu bar icon, or with ⌘Q.';
      } else {
        body = 'It stays in the tray, ready for the next link. Quit it from the tray icon.';
      }
      DesktopNotify.show('uwuFix is still running', body);
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
      final maximized = await windowManager.isMaximized();
      final fullScreen = await windowManager.isFullScreen();
      final kept = <String, Object?>{'maximized': maximized};
      if (!maximized && !fullScreen) {
        final bounds = await windowManager.getBounds();
        kept['bounds'] = {'x': bounds.left, 'y': bounds.top, 'width': bounds.width, 'height': bounds.height};
      }
      DesktopSettings.merge(kept);
    } catch (_) {}
  }

  /// A link the app was opened with, or that a second copy passed on.
  static void openLink(String link) {
    if (!handleLink(link)) {
      return;
    }
    show();
  }
}

/// Whether [text] is a link the app opens: a uwu: or web address.
bool _isLink(String text) {
  return text.startsWith('uwu:') || text.startsWith('http');
}

/// Where the app starts on the desktop: a widget's window, or the app itself.
Future<void> desktopMain(List<String> arguments) async {
  // desktop_multi_window starts each extra window as `main(['multi_window', id, json])`.
  if (arguments.isNotEmpty && arguments.first == 'multi_window') {
    String idText;
    if (arguments.length > 1) {
      idText = arguments[1];
    } else {
      idText = '';
    }
    int windowId;
    final parsedId = int.tryParse(idText);
    if (parsedId != null) {
      windowId = parsedId;
    } else {
      windowId = 0;
    }
    Map<String, dynamic> extra;
    if (arguments.length > 2 && arguments[2].isNotEmpty) {
      extra = Map<String, dynamic>.from(jsonDecode(arguments[2]) as Map);
    } else {
      extra = <String, dynamic>{};
    }
    await runWidgetWindow(windowId, extra);
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
  GlassWindow.instance.start();
  await DesktopNotify.init(shortcut: !Desktop.fromSource);
  if (!Desktop.fromSource) {
    registerLinkScheme();
  }
  await _startAtSignIn();

  final updater = DesktopUpdater(info.version);
  Desktop.updater = updater;
  AppUpdate.desktop = updater;

  // Links from a second copy, the Dock, the Jump List and macOS's URL events (the runners).
  Desktop.channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'open':
        final callArguments = call.arguments;
        final links = <String>[];
        if (callArguments is List) {
          for (final argument in callArguments) {
            links.add('$argument');
          }
        } else {
          links.add('$callArguments');
        }
        var anyLink = false;
        for (final link in links) {
          if (_isLink(link)) {
            anyLink = true;
            Desktop.openLink(link);
          }
        }
        // Nothing to open: just the window, brought forward.
        if (!anyLink) {
          await Desktop.show();
        }
      case 'activate':
        await Desktop.show();
      case 'task':
        await Desktop.show();
        runTask('${call.arguments}');
    }
    return null;
  });
  DesktopNotify.onClick = (payload) async {
    await Desktop.show();
    switch (payload) {
      case 'update':
        if (updater.ready) {
          await updater.install();
        }
      case 'release':
        await Native.call('Fixup', 'open', {'url': releasesLatest}).catchError((_) {
          return null;
        });
      default:
        if (payload != null && payload.startsWith('file:')) {
          await revealFile(payload.substring(5));
        } else if (payload != null && payload.isNotEmpty) {
          handleLink(payload);
        }
    }
  };

  final launchLinks = <String>[];
  String? task;
  for (final argument in arguments) {
    if (_isLink(argument)) {
      launchLinks.add(argument);
    }
  }
  // A link for one of UwU Apps' other apps, which only started this copy to pass it on.
  if (launchLinks.isNotEmpty && launchLinks.every(isOthersLink)) {
    for (final link in launchLinks) {
      handleLink(link);
    }
    exit(0);
  }
  // A Jump List task (Windows) or Dock item (macOS) that started the app.
  for (final argument in arguments) {
    if (argument.startsWith('--task=')) {
      task = argument.substring(7);
      break;
    }
  }
  runApp(DesktopRoot(launchLinks: launchLinks, launchTask: task));
}

Future<void> _startAtSignIn() async {
  try {
    final appImage = Platform.environment['APPIMAGE'];
    String appPath;
    if (appImage != null) {
      appPath = appImage;
    } else {
      appPath = Platform.resolvedExecutable;
    }
    launchAtStartup.setup(appName: Desktop.name, appPath: appPath, packageName: Desktop.appId);
    // On from the first run of an installed copy; the person's choice sticks once made.
    if (!Desktop.fromSource && DesktopSettings.get('loginChosen') != true && !await launchAtStartup.isEnabled()) {
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

Future<void> setStartAtSignIn(bool enabled) async {
  DesktopSettings.set('loginChosen', true);
  try {
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
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
  State<DesktopRoot> createState() {
    return DesktopRootState();
  }
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
    await GlassWindow.instance.apply(again: true);
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
    if (DesktopSettings.get('setupDone') != true) {
      await showWelcome();
      return;
    }
    await _mainWindow();
  }

  Future<void> showWelcome() async {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: Desktop.mac);
    await GlassWindow.instance.apply(again: true);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(620, 560));
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    await windowManager.setSize(const Size(940, 660));
    await windowManager.center();
    setState(() {
      _phase = 'welcome';
    });
    await windowManager.show();
  }

  /// Make it yours closed, either way: seen, and on to the app.
  Future<void> welcomeDone() async {
    DesktopSettings.set('setupDone', true);
    await _mainWindow();
  }

  /// The main window: where it was last (if that's still on a screen), maximised unless it
  /// wasn't, then the tray, update checks, and whatever the app was launched with.
  Future<void> _mainWindow() async {
    if (_phase == 'main') {
      await Desktop.show();
      return;
    }
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: Desktop.mac);
    await GlassWindow.instance.apply(again: true);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(Desktop.minimumSize);
    final settings = DesktopSettings.read();
    final bounds = settings['bounds'];
    if (bounds is Map && await _onScreen(bounds)) {
      await windowManager.setBounds(Rect.fromLTWH((bounds['x'] as num).toDouble(), (bounds['y'] as num).toDouble(), (bounds['width'] as num).toDouble(), (bounds['height'] as num).toDouble()));
    } else {
      await windowManager.setSize(Desktop.defaultSize);
      await windowManager.center();
    }
    setState(() {
      _phase = 'main';
    });
    // Maximised unless it was last closed un-maximised.
    if (settings['maximized'] != false) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
    await Tray.init();
    Desktop.updater?.schedule();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final link in widget.launchLinks) {
        handleLink(link);
      }
      if (DesktopNotify.launchPayload != null) {
        DesktopNotify.onClick(DesktopNotify.launchPayload);
      }
      if (widget.launchTask != null) {
        runTask(widget.launchTask!);
      }
      reopenWidgetWindows();
      Timer(const Duration(milliseconds: 900), () {
        Tours.init(openedByLink: widget.launchLinks.isNotEmpty || widget.launchTask != null);
      });
    });
  }

  // A kept place is used only if it's still on a screen (a monitor unplugged since).
  Future<bool> _onScreen(Map bounds) async {
    final left = (bounds['x'] as num?)?.toDouble();
    final top = (bounds['y'] as num?)?.toDouble();
    final width = (bounds['width'] as num?)?.toDouble();
    final height = (bounds['height'] as num?)?.toDouble();
    if (left == null || top == null || width == null || height == null || width < 200 || height < 200) {
      return false;
    }
    return left > -width + 80 && top > -20 && left < 10000 && top < 10000;
  }

  // ---------- the window's events ----------

  @override
  void onWindowClose() async {
    if (Desktop.quitting) {
      return;
    }
    if (_phase == 'welcome') {
      // Closing Make it yours changes nothing, but still counts as having seen it.
      await welcomeDone();
      return;
    }
    if (_phase == 'splash') {
      return;
    }
    await Desktop.hide();
  }

  /// Keeps the window's place, half a second after it last changed.
  void _keepBoundsSoon() {
    if (_phase != 'main') {
      return;
    }
    _boundsTimer?.cancel();
    _boundsTimer = Timer(const Duration(milliseconds: 500), Desktop.keepBounds);
  }

  // Leaving full screen puts Windows' frame back as it was, without the backdrop's.
  @override
  void onWindowLeaveFullScreen() {
    GlassWindow.instance.apply(again: true);
  }

  @override
  void onWindowMoved() {
    _keepBoundsSoon();
  }

  @override
  void onWindowResized() {
    _keepBoundsSoon();
  }

  @override
  void onWindowMaximize() {
    _keepBoundsSoon();
  }

  @override
  void onWindowUnmaximize() {
    _keepBoundsSoon();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case 'splash':
        return UwuFixApp(home: SplashScreen(updater: Desktop.updater!, onDone: splashDone));
      case 'welcome':
        return UwuFixApp(home: WelcomeScreen(onDone: welcomeDone));
      default:
        return const UwuFixApp(desktopShell: DesktopShell());
    }
  }
}

/// What's copied, cleaned: the tray's and the Jump List's Fix copied link.
Future<void> fixCopied() async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  String text;
  final copiedText = data?.text;
  if (copiedText != null) {
    text = copiedText.trim();
  } else {
    text = '';
  }
  AppNav.showPage('home');
  if (text.isEmpty) {
    AppNav.say('Nothing’s copied. Paste or type a link to fix it.');
    return;
  }
  Links.open(text);
}

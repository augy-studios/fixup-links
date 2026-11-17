// The tray icon (the menu bar on macOS), docs/desktop-features-spec.md §4. Its tooltip is the
// app's name. Clicking it (Windows and Linux) shows and focuses the main window, or hides it if
// it's already in front; macOS opens the menu. The menu, rebuilt each time it opens:
//
//   Restart to update to x.y.z / Download version x.y.z    (while there's one)
//   Open uwuFix
//   Fix copied link, History                               (uwuFix's two most-used places)
//   Add a Fix a link widget
//   Make it yours...
//   Check for updates...                                   ("Checking for updates..." while it runs)
//   Start when I sign in                                   (a check box)
//   Quit
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import '../features/update/update_bar.dart';
import '../native/native_bridge.dart';
import 'desktop.dart';
import 'notify.dart';
import 'updater.dart';

/// The tray icon and its menu, and what clicking either does.
class Tray with TrayListener {
  Tray._();
  static final Tray _instance = Tray._();
  static bool _started = false;

  /// The icon file for this system: Windows' .ico, macOS's template image, or a PNG.
  static String get _iconPath {
    if (Platform.isWindows) {
      return 'assets/desktop/tray.ico';
    }
    if (Platform.isMacOS) {
      return 'assets/desktop/tray_template.png';
    }
    return 'assets/desktop/tray.png';
  }

  static Future<void> init() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      await trayManager.setIcon(_iconPath, isTemplate: Platform.isMacOS);
      if (!Platform.isLinux) {
        await trayManager.setToolTip(Desktop.name);
      }
      trayManager.addListener(_instance);
      AppUpdate.I.addListener(_instance._rebuild);
      await _instance._rebuild();
    } catch (_) {
      // No tray here (some Linux desktops): the window's close button then really closes it.
      _started = false;
    }
  }

  static Future<void> dispose() async {
    if (!_started) {
      return;
    }
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  /// The menu, as it should be now: the update item while there's one, and the sign-in box ticked
  /// or not.
  Future<void> _rebuild() async {
    final update = AppUpdate.I;
    final updater = Desktop.updater;
    final login = await startsAtSignIn();
    final checking = update.state == 'checking';
    String checkLabel;
    if (checking) {
      checkLabel = 'Checking for updates...';
    } else {
      checkLabel = 'Check for updates...';
    }
    final items = <MenuItem>[];
    if (updater?.ready == true) {
      items.add(MenuItem(key: 'restart', label: 'Restart to update to ${update.version}'));
      items.add(MenuItem.separator());
    } else if (update.version != null && update.state == 'available' && updater?.canInstall == false) {
      items.add(MenuItem(key: 'download', label: 'Download version ${update.version}'));
      items.add(MenuItem.separator());
    }
    items.addAll([
      MenuItem(key: 'open', label: 'Open uwuFix'),
      MenuItem(key: 'paste', label: 'Fix copied link'),
      MenuItem(key: 'history', label: 'History'),
      MenuItem(key: 'widget', label: 'Add a Fix a link widget'),
      MenuItem(key: 'welcome', label: 'Make it yours...'),
      MenuItem.separator(),
      MenuItem(key: 'check', label: checkLabel, disabled: checking),
      MenuItem.checkbox(key: 'login', label: 'Start when I sign in', checked: login),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]);
    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu();
    } else {
      Desktop.toggle();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    await _rebuild();
    // Windows only closes a tray menu on a click outside it when the menu's window is in front
    // (TrackPopupMenu's rule), so bring ours there first; without it the menu, and the tray's
    // overflow flyout behind it, stay open. It's the window's focus, not showing it: a hidden
    // window stays hidden.
    // ignore: deprecated_member_use
    await trayManager.popUpContextMenu(bringAppToFront: Platform.isWindows);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'restart':
        await Desktop.updater?.install();
      case 'download':
        await Native.call('Fixup', 'open', {'url': releasesLatest}).catchError((_) {
          return null;
        });
      case 'open':
        await Desktop.show();
      case 'paste' || 'history' || 'widget' || 'welcome':
        if (menuItem.key != 'widget') {
          await Desktop.show();
        }
        runTask(menuItem.key!);
      case 'check':
        await _check();
      case 'login':
        await setStartAtSignIn(!(await startsAtSignIn()));
        await _rebuild();
      case 'quit':
        await Desktop.quit();
    }
  }

  // Check for updates... always says what it found.
  Future<void> _check() async {
    final update = AppUpdate.I;
    await update.check(asked: true);
    switch (update.state) {
      case 'upToDate':
        await DesktopNotify.show('uwuFix is up to date', '${Desktop.version} is the newest version.');
      case 'failed':
        await DesktopNotify.show('Couldn’t check for updates', 'Check you’re online, then try again.');
      case 'available':
        if (Desktop.updater?.canInstall == true) {
          await DesktopNotify.show('Downloading uwuFix ${update.version}', 'It’s ready to install in a minute or two.');
          await update.update();
        } else {
          await DesktopNotify.show('uwuFix ${update.version} is out', 'Click to download it from GitHub.', payload: 'release');
        }
    }
    await _rebuild();
  }
}

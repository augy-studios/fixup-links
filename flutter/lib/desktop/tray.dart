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

class Tray with TrayListener {
  Tray._();
  static final Tray _i = Tray._();
  static bool _started = false;

  static Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      await trayManager.setIcon(
        Platform.isWindows ? 'assets/desktop/tray.ico' : Platform.isMacOS ? 'assets/desktop/tray_template.png' : 'assets/desktop/tray.png',
        isTemplate: Platform.isMacOS,
      );
      if (!Platform.isLinux) await trayManager.setToolTip(Desktop.name);
      trayManager.addListener(_i);
      AppUpdate.I.addListener(_i._rebuild);
      await _i._rebuild();
    } catch (_) {
      // No tray here (some Linux desktops): the window's close button then really closes it.
      _started = false;
    }
  }

  static Future<void> dispose() async {
    if (!_started) return;
    try {
      await trayManager.destroy();
    } catch (_) {}
  }

  Future<void> _rebuild() async {
    final u = AppUpdate.I;
    final updater = Desktop.updater;
    final login = await startsAtSignIn();
    final checking = u.state == 'checking';
    await trayManager.setContextMenu(Menu(items: [
      if (updater?.ready == true) ...[
        MenuItem(key: 'restart', label: 'Restart to update to ${u.version}'),
        MenuItem.separator(),
      ] else if (u.version != null && u.state == 'available' && updater?.canInstall == false) ...[
        MenuItem(key: 'download', label: 'Download version ${u.version}'),
        MenuItem.separator(),
      ],
      MenuItem(key: 'open', label: 'Open uwuFix'),
      MenuItem(key: 'paste', label: 'Fix copied link'),
      MenuItem(key: 'history', label: 'History'),
      MenuItem(key: 'widget', label: 'Add a Fix a link widget'),
      MenuItem(key: 'welcome', label: 'Make it yours...'),
      MenuItem.separator(),
      MenuItem(key: 'check', label: checking ? 'Checking for updates...' : 'Check for updates...', disabled: checking),
      MenuItem.checkbox(key: 'login', label: 'Start when I sign in', checked: login),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit'),
    ]));
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
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'restart':
        await Desktop.updater?.install();
      case 'download':
        await Native.call('Fixup', 'open', {'url': releasesLatest}).catchError((_) => null);
      case 'open':
        await Desktop.show();
      case 'paste' || 'history' || 'widget' || 'welcome':
        if (item.key != 'widget') await Desktop.show();
        runTask(item.key!);
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
    final u = AppUpdate.I;
    await u.check(asked: true);
    switch (u.state) {
      case 'upToDate':
        await DeskNotify.show('uwuFix is up to date', '${Desktop.version} is the newest version.');
      case 'failed':
        await DeskNotify.show('Couldn’t check for updates', 'Check you’re online, then try again.');
      case 'available':
        if (Desktop.updater?.canInstall == true) {
          await DeskNotify.show('Downloading uwuFix ${u.version}', 'It’s ready to install in a minute or two.');
          await u.update();
        } else {
          await DeskNotify.show('uwuFix ${u.version} is out', 'Click to download it from GitHub.', payload: 'release');
        }
    }
    await _rebuild();
  }
}

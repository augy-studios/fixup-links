// System notifications on the desktop (docs/desktop-features-spec.md §7), with the app's icon and
// name: new versions (updater.dart), "still running" (desktop.dart), "Screenshot saved"
// (screenshot.dart). Each carries a payload; clicking one brings the main window forward and does
// what the payload says (an in-app address, "update", "release", or a file to show in its folder).
//
// local_notifier, which has no Android side (the phone's notifications are Firebase's): Windows'
// toasts through its Start menu shortcut (made by the installer, given the app's id by WinToast),
// macOS's notification centre (it asks once), and Linux's freedesktop service.
import 'package:local_notifier/local_notifier.dart';

class DeskNotify {
  DeskNotify._();

  static bool _ready = false;

  /// What a click does: set by desktop.dart.
  static void Function(String? payload) onClick = (_) {};

  /// A notification clicked to start the app, delivered once the app's up. (local_notifier has
  /// none: a click with the app closed only opens it.)
  static String? launchPayload;

  /// [shortcut]: let Windows' notifications make or fix the Start menu shortcut (an installed copy).
  static Future<void> init({bool shortcut = true}) async {
    try {
      await localNotifier.setup(appName: 'uwuFix', shortcutPolicy: shortcut ? ShortcutPolicy.requireCreate : ShortcutPolicy.ignore);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<void> show(String title, String body, {String? payload}) async {
    if (!_ready) return;
    try {
      final n = LocalNotification(title: title, body: body);
      n.onClick = () => onClick(payload);
      await n.show();
    } catch (_) {
      // No notification service (a bare Linux session): nothing shown.
    }
  }
}

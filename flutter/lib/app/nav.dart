// Getting around the app from anywhere: its pages, messages at the bottom, and, on the desktop,
// the title bar's Back and Forward through the pages visited.
//
// The app's pages, by id, as the site has its places (js/tour.js):
//   home     the cleaner
//   history  every link cleaned
//   sync     Share history with another device
//   look     Look: Material You or the UwU Apps look, light or dark, the brand colour
// On a phone the others open over home; on the desktop they're the navigation rail's, beside it.
import 'package:flutter/material.dart';

class AppNav {
  AppNav._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static BuildContext? get context => navigatorKey.currentContext;

  /// Report a bug's Screenshot a page (features/bug/bug_report.dart): what's drawn (the app, not
  /// the button floating over it), and whether that button is out.
  static final shotKey = GlobalKey();
  static final shooting = ValueNotifier<bool>(false);

  /// A screen of its own over the app (Report a bug), not one of [pages].
  static Future<void> push(Widget screen, {required String name}) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    await nav.push(MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: (_) => screen));
  }

  static const pages = ['home', 'history', 'sync', 'look'];

  /// The page on show.
  static final page = ValueNotifier<String>('home');

  /// How a page opens: set by the shell (the phone's pushes it, the desktop's switches to it).
  static void Function(String id, Map<String, Object?> args) opener = (_, _) {};

  /// Where the desktop's Back and Forward go.
  static final List<String> _back = [];
  static final List<String> _forward = [];
  static final canGo = ValueNotifier<(bool, bool)>((false, false));

  static void showPage(String id, [Map<String, Object?> args = const {}]) {
    if (!pages.contains(id)) return;
    if (id != page.value) {
      _back.add(page.value);
      _forward.clear();
      _tellCanGo();
    }
    opener(id, args);
  }

  /// The shell, saying which page is on show now (after a push, a pop, or a switch).
  static void shown(String id) {
    if (page.value == id) return;
    page.value = id;
  }

  static void back() {
    if (_back.isEmpty) return;
    _forward.add(page.value);
    final id = _back.removeLast();
    _tellCanGo();
    opener(id, const {});
  }

  static void forward() {
    if (_forward.isEmpty) return;
    _back.add(page.value);
    final id = _forward.removeLast();
    _tellCanGo();
    opener(id, const {});
  }

  static void _tellCanGo() => canGo.value = (_back.isNotEmpty, _forward.isNotEmpty);

  /// A message at the bottom, as the site's toast.
  static void say(String text, {String? action, VoidCallback? onAction, Duration duration = const Duration(milliseconds: 2200)}) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(text),
      duration: action == null ? duration : const Duration(seconds: 6),
      action: action == null ? null : SnackBarAction(label: action, onPressed: onAction ?? () {}),
    ));
  }

  /// A page's reload (the desktop's Reload and F5): whatever the page on show does again.
  static final Map<String, Future<void> Function()> reloaders = {};
  static final reloading = ValueNotifier<bool>(false);

  static Future<void> reload() async {
    final f = reloaders[page.value];
    if (f == null || reloading.value) return;
    reloading.value = true;
    try {
      await f();
    } finally {
      reloading.value = false;
    }
  }
}

// The phone's shell: the update bar at the top, the home page under it with the Edge Tray pinned
// top right, and the other pages (History, Share history, Look) opening over it. Back closes
// what's open, then "Press back again to exit", and the second press sends the app to the
// background rather than closing it.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../features/history/history_page.dart';
import '../features/home/home_page.dart';
import '../features/look/look_page.dart';
import '../features/sync/sync_page.dart';
import '../features/update/update_bar.dart';
import '../native/native_bridge.dart';
import 'edge_tray.dart';
import 'nav.dart';

/// Keeps AppNav.page in step with the pages pushed and popped.
class PageObserver extends NavigatorObserver {
  void _tell(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && AppNav.pages.contains(name)) {
      AppNav.shown(name);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _tell(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _tell(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _tell(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _tell(newRoute);
  }
}

/// The page with this id; [embedded] when it sits beside others rather than over home.
Widget pageFor(String id, Map<String, Object?> arguments, {bool embedded = false}) {
  switch (id) {
    case 'history':
      return HistoryPage(pane: embedded);
    case 'sync':
      return SyncPage(joinCode: arguments['join'] as String?, embedded: embedded);
    case 'look':
      return LookPage(embedded: embedded);
    default:
      return const HomePage();
  }
}

class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key});

  @override
  State<PhoneShell> createState() {
    return _PhoneShellState();
  }
}

class _PhoneShellState extends State<PhoneShell> {
  DateTime? _backPressedAt;

  @override
  void initState() {
    super.initState();
    AppNav.opener = (id, arguments) {
      final navigator = AppNav.navigatorKey.currentState;
      if (navigator == null) {
        return;
      }
      // Over home, never one page on another: each is a step from home.
      navigator.popUntil((route) {
        return route.isFirst;
      });
      if (id == 'home') {
        AppNav.shown('home');
        return;
      }
      navigator.push(MaterialPageRoute<void>(
        settings: RouteSettings(name: id),
        builder: (_) {
          return pageFor(id, arguments);
        },
      ));
    };
  }

  /// Back on home: the first press warns, a second within 2 s sends the app to the background.
  void _back() {
    final now = DateTime.now();
    if (_backPressedAt != null && now.difference(_backPressedAt!) < const Duration(seconds: 2)) {
      _backPressedAt = null;
      Native.call('Fixup', 'background').catchError((_) {
        return null;
      });
      return;
    }
    _backPressedAt = now;
    AppNav.say('Press back again to exit', duration: const Duration(seconds: 2));
  }

  /// The update bar over home, with the Edge Tray pinned top right and room made for it.
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _back();
        }
      },
      child: Scaffold(
        body: Column(children: [
          const AppUpdateBar(),
          Expanded(
            child: Stack(children: [
              // Room for the Edge Tray while it's out, as the site makes it: its room replaces the
              // page's own right padding rather than adding to it. Tucked away, only the brand
              // line steps in, clear of its tab.
              Positioned.fill(
                child: ValueListenableBuilder(
                  valueListenable: EdgeTray.open,
                  builder: (context, open, _) {
                    final room = EdgeTray.roomFor(context);
                    final extra = math.max(0.0, room - HomePage.sidePadding);
                    Duration duration;
                    if (MediaQuery.of(context).disableAnimations) {
                      duration = Duration.zero;
                    } else {
                      duration = EdgeTray.time;
                    }
                    return AnimatedPadding(
                      duration: duration,
                      curve: EdgeTray.ease,
                      padding: EdgeInsets.only(right: extra),
                      child: HomePage(trailingSpace: EdgeTray.brandStepFor(context, HomePage.sidePadding + extra)),
                    );
                  },
                ),
              ),
              Positioned(
                right: 0,
                top: top + 14,
                // The update bar's own top padding is already round the status bar when it shows.
                child: const EdgeTray(),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

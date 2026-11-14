// The phone's shell: the update bar at the top, the home page under it with the Edge Tray pinned
// top right, and the other pages (History, Share history, Look) opening over it. Back closes
// what's open, then "Press back again to exit", and the second press sends the app to the
// background rather than closing it.

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
  void _tell(Route<dynamic>? r) {
    final name = r?.settings.name;
    if (name != null && AppNav.pages.contains(name)) AppNav.shown(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _tell(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _tell(previousRoute);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _tell(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _tell(newRoute);
}

Widget pageFor(String id, Map<String, Object?> args, {bool embedded = false}) => switch (id) {
      'history' => HistoryPage(pane: embedded),
      'sync' => SyncPage(joinCode: args['join'] as String?, embedded: embedded),
      'look' => LookPage(embedded: embedded),
      _ => const HomePage(),
    };

class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key});

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  DateTime? _backAt;

  @override
  void initState() {
    super.initState();
    AppNav.opener = (id, args) {
      final nav = AppNav.navigatorKey.currentState;
      if (nav == null) return;
      // Over home, never one page on another: each is a step from home.
      nav.popUntil((r) => r.isFirst);
      if (id == 'home') {
        AppNav.shown('home');
        return;
      }
      nav.push(MaterialPageRoute<void>(settings: RouteSettings(name: id), builder: (_) => pageFor(id, args)));
    };
  }

  void _back() {
    final now = DateTime.now();
    if (_backAt != null && now.difference(_backAt!) < const Duration(seconds: 2)) {
      _backAt = null;
      Native.call('Fixup', 'background').catchError((_) => null);
      return;
    }
    _backAt = now;
    AppNav.say('Press back again to exit', duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: Column(children: [
          const AppUpdateBar(),
          Expanded(
            child: Stack(children: [
              // Room for the Edge Tray while it's out, as the site makes it; tucked away, only the
              // brand line steps in, clear of its tab.
              Positioned.fill(
                child: ValueListenableBuilder(
                  valueListenable: EdgeTray.open,
                  builder: (context, open, _) {
                    final room = EdgeTray.roomFor(MediaQuery.sizeOf(context).width);
                    return AnimatedPadding(
                      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 340),
                      curve: const Cubic(0.2, 0.8, 0.2, 1),
                      padding: EdgeInsets.only(right: room),
                      child: HomePage(trailingSpace: room > 0 ? 0 : 30),
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

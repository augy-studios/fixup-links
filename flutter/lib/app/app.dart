// The app's root: the look (theme/theme.dart), the navigator every page opens through
// (app/nav.dart), and which screen it is: the quick screen (Android's FixActivity), the desktop's
// shell (lib/desktop/chrome.dart), or the phone's (app/shell.dart).
import 'package:flutter/material.dart';

import '../features/bug/bug_report.dart';
import '../theme/theme.dart';
import 'nav.dart';
import 'quick.dart';
import 'shell.dart';

class UwuFixApp extends StatefulWidget {
  const UwuFixApp({super.key, this.desktopShell, this.home});

  /// The desktop's shell, from lib/desktop/ (left out of the phone's app).
  final Widget? desktopShell;

  /// For tests and screenshots: a screen of their own.
  final Widget? home;

  @override
  State<UwuFixApp> createState() => _UwuFixAppState();
}

class _UwuFixAppState extends State<UwuFixApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A new wallpaper or accent colour while the app was away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) AppLook.I.readDevice();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppLook.I,
        builder: (context, _) {
          final look = AppLook.I;
          return MaterialApp(
            title: 'uwuFix',
            debugShowCheckedModeBanner: false,
            navigatorKey: AppNav.navigatorKey,
            scaffoldMessengerKey: AppNav.messengerKey,
            navigatorObservers: [PageObserver()],
            theme: look.theme(Brightness.light),
            darkTheme: look.theme(Brightness.dark),
            themeMode: look.themeMode,
            // Text as large as the device asks, up to twice, so layouts hold.
            // Report a bug's Screenshot a page draws what's in the RepaintBoundary, and its button
            // floats over it, outside, so it isn't in the picture.
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              maxScaleFactor: 2,
              child: Stack(children: [
                Positioned.fill(child: RepaintBoundary(key: AppNav.shotKey, child: child!)),
                ValueListenableBuilder(
                  valueListenable: AppNav.shooting,
                  builder: (context, on, _) => on ? const ShotBar() : const SizedBox.shrink(),
                ),
              ]),
            ),
            home: widget.home ?? (isQuick ? const QuickScreen() : widget.desktopShell ?? const PhoneShell()),
          );
        },
      );
}

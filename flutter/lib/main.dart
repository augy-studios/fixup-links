// uwuFix 1.1.0: the app's own screens in Flutter, for Android, Windows, macOS and Linux, where
// 1.0.0 and 1.0.1 were the site in a WebView on Android. The site's features, words, stored data
// and API are the same (README.md); Android's native parts are Java plugins
// (native/native_bridge.dart), and the desktop's its own layer (desktop/).
import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/links.dart';
import 'app/nav.dart';
import 'app/quick.dart';
import 'data/migrate.dart';
import 'data/store.dart';
import 'desktop/desktop.dart';
import 'features/notify/notify_sheet.dart';
import 'features/tour/tour.dart';
import 'features/update/update_bar.dart';
import 'native/native_bridge.dart';
import 'theme/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (onDesktop) return desktopMain(args);

  await Store.open();
  await Native.start();
  // Everything the WebView app kept, the first time (data/migrate.dart).
  final migrated = await Migrate.run();
  await AppLook.I.readDevice();
  runApp(const UwuFixApp());
  if (isQuick) return;

  // What the app was opened with (a site link, a uwu://fix/ link, a notification), then and later.
  var openedByLink = false;
  Native.on('Fixup', 'open', (d) {
    openedByLink = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => Links.open('${d['url'] ?? ''}'));
  });
  listenForPushes();
  AppUpdate.I.start();
  // A link that opened the app came for that, not a tour.
  Timer(const Duration(milliseconds: 900), () => Tours.init(openedByLink: openedByLink));
  if (migrated > 0) {
    Timer(const Duration(milliseconds: 600), () => AppNav.say('Your history and settings are here from before.', duration: const Duration(seconds: 5)));
  }
}

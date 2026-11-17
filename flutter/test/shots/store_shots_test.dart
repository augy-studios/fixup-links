// The app's screens for the Google Play listing's pictures (docs/store-assets/, tool/store_assets.mjs
// frames them), rendered by Flutter's test renderer from fixed data with the app's real fonts, so
// they come out the same whenever they're taken. As sgbus-timings' test/shots/.
//
//   SHOTS=all flutter test test/shots/            every shot, into build/shots/
//   SHOTS=phone-home,desktop flutter test test/shots/   only those (by the start of their names)
//   SHOTS=glass flutter test test/shots/          the desktop's glass looks, to look at
//
// Skipped unless SHOTS is set, so `flutter test` on CI stays quick.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwufix/api/resolve.dart';
import 'package:uwufix/app/app.dart';
import 'package:uwufix/app/nav.dart';
import 'package:uwufix/app/quick.dart';
import 'package:uwufix/app/shell.dart';
import 'package:uwufix/data/history.dart';
import 'package:uwufix/data/store.dart';
import 'package:uwufix/desktop/chrome.dart';
import 'package:uwufix/features/home/fixer.dart';
import 'package:uwufix/features/sync/sync_page.dart';
import 'package:uwufix/features/tour/tour.dart';
import 'package:uwufix/native/native_bridge.dart';
import 'package:uwufix/theme/theme.dart';

final _shotsWanted = Platform.environment['SHOTS'];
final _outputDirectory = Directory('build/shots');

bool _want(String name) {
  final wanted = _shotsWanted;
  if (wanted == null || wanted.isEmpty || wanted == 'all') {
    return true;
  }
  for (final namePrefix in wanted.split(',')) {
    if (name.startsWith(namePrefix)) {
      return true;
    }
  }
  return false;
}

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(file).readAsBytesSync())));
  }
  await loader.load();
}

/// Loads the fonts the shots are drawn in: Jua, Flutter's own Roboto and Material icons, and
/// Windows' fonts where they're there.
Future<void> _fonts() async {
  final environment = Platform.environment;
  final flutterRoot = environment['FLUTTER_ROOT'];
  String root;
  if (flutterRoot != null) {
    root = flutterRoot;
  } else {
    final userProfile = environment['USERPROFILE'];
    String? home;
    if (userProfile != null) {
      home = userProfile;
    } else {
      home = environment['HOME'];
    }
    root = '$home/flutter';
  }
  final materialFonts = '$root/bin/cache/artifacts/material_fonts';
  final roboto = ['$materialFonts/roboto-regular.ttf', '$materialFonts/roboto-medium.ttf', '$materialFonts/roboto-bold.ttf', '$materialFonts/roboto-light.ttf'];
  await _font('Jua', ['assets/fonts/Jua-Regular.ttf']);
  await _font('Roboto', roboto);
  await _font('FlutterTest', roboto);
  await _font('MaterialIcons', ['$materialFonts/materialicons-regular.otf']);
  // What a device falls back to for characters Jua hasn't, and emoji: Windows' own stand in.
  if (File('C:/Windows/Fonts/segoeui.ttf').existsSync()) {
    await _font('Segoe UI', ['C:/Windows/Fonts/segoeui.ttf']);
  }
  if (File('C:/Windows/Fonts/seguiemj.ttf').existsSync()) {
    await _font('Segoe UI Emoji', ['C:/Windows/Fonts/seguiemj.ttf']);
  }
  // Fluent 2's font (the glass shots), or Roboto standing in for it off Windows.
  const segoeVariable = 'C:/Windows/Fonts/SegUIVar.ttf';
  if (File(segoeVariable).existsSync()) {
    await _font('Segoe UI Variable Text', [segoeVariable]);
  } else {
    await _font('Segoe UI Variable Text', roboto);
  }
}

// Sam's history: real links, as people fix them.
final _now = DateTime.utc(2026, 11, 14, 4, 30);
List<Map<String, String>> _links = [
  {'o': 'https://www.instagram.com/reel/C9xYz12AbCd/?igsh=MWZ0cnBhZ2lzNWh5bg==', 'c': 'https://www.oginstagram.com/reel/C9xYz12AbCd/', 'p': 'Instagram', 't': 'Cat learns to skateboard 🛹'},
  {'o': 'https://x.com/uwuapps/status/1856001234567890123?s=46&t=Zq1x', 'c': 'https://fixupx.com/i/status/1856001234567890123', 'p': 'X / Twitter', 't': 'UwU Apps on X: uwuFix 1.1.0 is out'},
  {'o': 'https://www.tiktok.com/@cooking/video/7436123456789012345?is_from_webapp=1&sender_device=pc', 'c': 'https://tnktok.com/@cooking/video/7436123456789012345', 'p': 'TikTok', 't': '15-minute laksa'},
  {'o': 'https://www.reddit.com/r/singapore/comments/1gq2abc/hawker_tips/?share_id=Xy7&utm_medium=android_app', 'c': 'https://www.vxreddit.com/r/singapore/comments/1gq2abc/hawker_tips/', 'p': 'Reddit', 't': 'Hawker centre tips for newcomers'},
  {'o': 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=a1b2c3', 'c': 'https://fxspotify.com/track/4uLU6hMCjMI75M1A2tKUQC', 'p': 'Spotify', 't': 'Never Gonna Give You Up'},
  {'o': 'https://youtu.be/dQw4w9WgXcQ?si=Kq9', 'c': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'p': 'YouTube', 't': 'A video you know'},
  {'o': 'https://bsky.app/profile/augy.bsky.social/post/3lb2xyz?ref_src=embed', 'c': 'https://fxbsky.app/profile/augy.bsky.social/post/3lb2xyz', 'p': 'Bluesky', 't': 'Augy on Bluesky'},
  {'o': 'https://www.amazon.com/dp/B0C1234567?ref_=nav&tag=deals-20&th=1', 'c': 'https://www.amazon.com/dp/B0C1234567?th=1', 'p': 'Amazon', 't': 'Mechanical keyboard'},
];

/// The stored values for a shot: Sam's history, the tours seen, and the look asked for.
Map<String, String> _store({String look = 'you', String mode = 'light', String colour = 'classic'}) {
  final items = <Map<String, Object?>>[];
  for (var index = 0; index < _links.length; index++) {
    var extraHours = 0;
    if (index > 3) {
      extraHours = 30;
    }
    items.add({
      'id': _now.millisecondsSinceEpoch - index * 3600 * 1000 * 5,
      'original': _links[index]['o'],
      'cleaned': _links[index]['c'],
      'platform': _links[index]['p'],
      'title': _links[index]['t'],
      'date': isoMilliseconds(_now.subtract(Duration(hours: index * 5 + extraHours))),
    });
  }
  return {
    'tour.welcome': 'done',
    'tour.pages': '["history","sync","look"]',
    historyKey: _encode(items),
    'uwufix.look': look,
    'uwufix.mode': mode,
    'uwufix.colorTheme': colour,
  };
}

String _encode(Object value) {
  return const JsonCodecLite().encode(value);
}

/// A small JSON writer for the shots' data: numbers, booleans, strings, lists and maps.
class JsonCodecLite {
  const JsonCodecLite();

  String encode(Object value) {
    return _encodeValue(value);
  }

  String _encodeValue(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is num || value is bool) {
      return '$value';
    }
    if (value is String) {
      return '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    }
    if (value is List) {
      final parts = <String>[];
      for (final item in value) {
        parts.add(_encodeValue(item));
      }
      return '[${parts.join(',')}]';
    }
    if (value is Map) {
      final parts = <String>[];
      for (final entry in value.entries) {
        parts.add('${_encodeValue('${entry.key}')}:${_encodeValue(entry.value)}');
      }
      return '{${parts.join(',')}}';
    }
    return '"$value"';
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 14]) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// One shot: [build] in the app, at [size] logical pixels and [ratio], into build/shots/NAME.png.
Future<void> _shot(WidgetTester tester, String name, Size size, double ratio, Map<String, String> store, Widget Function() build,
    {Future<void> Function(WidgetTester tester)? then, EdgeInsets padding = const EdgeInsets.only(top: 28, bottom: 18)}) async {
  if (!_want(name)) {
    return;
  }
  Store.memory(store);
  AppNav.page.value = 'home';
  Fixer.I.clear();
  AppLook.now = () {
    return DateTime(2026, 11, 14, 12, 30);
  };
  // Material You's colours from a green wallpaper, as a phone would have them.
  AppLook.I.phoneLight = ColorScheme.fromSeed(seedColor: const Color(0xFF3F7D4B));
  AppLook.I.phoneDark = ColorScheme.fromSeed(seedColor: const Color(0xFF3F7D4B), brightness: Brightness.dark);
  AppLook.I.systemAccent = const Color(0xFF2E7D5B);
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  tester.view.padding = FakeViewPadding(top: padding.top * ratio, bottom: padding.bottom * ratio);
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(RepaintBoundary(key: key, child: UwuFixApp(home: build())));
  await _settle(tester);
  if (then != null) {
    await then(tester);
  }
  await _settle(tester);
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await _settle(tester, 4);
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  _outputDirectory.createSync(recursive: true);
  File('${_outputDirectory.path}/$name.png').writeAsBytesSync(bytes!);
  // Where each marked thing is, as fractions of the screen, for the store pictures' arrows.
  final rects = <String, List<double>>{};
  for (final target in TourTarget.allRects().entries) {
    final rect = target.value;
    rects[target.key] = [rect.left / size.width, rect.top / size.height, rect.right / size.width, rect.bottom / size.height];
  }
  File('${_outputDirectory.path}/$name.json').writeAsStringSync(_encode(rects));
}

Future<void> _fix(WidgetTester tester, String link) async {
  await tester.runAsync(() {
    return Fixer.I.fix(link);
  });
  // Fixing puts it in the history; the history shown stays Sam's.
}

Widget _phoneShell() {
  return const PhoneShell();
}

Widget _desktopShell() {
  return const DesktopShell();
}

Future<Map<String, dynamic>?> _noAnswer(String plugin, String method, Map<String, dynamic>? options) async {
  return null;
}

/// A page tour's second step, the tour started fresh.
Future<void> _tourSecondStep(WidgetTester tester) async {
  Tours.enabled = true;
  Tours.resetForTests();
  Tours.start_('home');
  await tester.pump(const Duration(seconds: 1));
  await _settle(tester, 10);
  await tester.tap(find.widgetWithText(FilledButton, 'Next'));
  await _settle(tester, 12);
  Tours.enabled = false;
}

/// The desktop's command box, with something typed in it.
Future<void> _typeCommand(WidgetTester tester) async {
  await tester.tap(find.byType(TextField).first);
  await _settle(tester, 4);
  await tester.enterText(find.byType(TextField).first, 'red');
}

const _shotTimeout = Timeout(Duration(minutes: 4));

void main() {
  setUpAll(() async {
    await _fonts();
    Api.fake = (_) async {
      return null;
    };
    Native.fake(const ['share', 'paste', 'open', 'push', 'update', 'checkupdate'], _noAnswer);
    Tours.enabled = false;
    SyncPage.previewOnly = true;
    DesktopShellState.preview = true;
  });

  // name, logical size, pixel ratio: phone 1080x2340-class, a 7" and a 10" tablet, and a desktop.
  final forms = {
    'phone': (const Size(412, 892), 3.0),
    'tablet7': (const Size(600, 1024), 2.0),
    'tablet10': (const Size(800, 1280), 2.0),
  };

  for (final form in forms.entries) {
    final (size, ratio) = form.value;
    final formName = form.key;
    testWidgets('$formName screens', timeout: _shotTimeout, (tester) async {
      await _shot(tester, '$formName-home', size, ratio, _store(), _phoneShell, then: (tester) async {
        await _fix(tester, 'https://www.instagram.com/reel/C9xYz12AbCd/?igsh=MWZ0cnBhZ2lzNWh5bg==&utm_source=ig_web_copy_link');
      });
      await _shot(tester, '$formName-home-uwu', size, ratio, _store(look: 'uwu', colour: 'classic'), _phoneShell, then: (tester) async {
        await _fix(tester, 'https://x.com/uwuapps/status/1856001234567890123?s=46&t=Zq1x');
      });
      await _shot(tester, '$formName-home-dark', size, ratio, _store(look: 'uwu', mode: 'dark', colour: 'not-green-2'), _phoneShell, then: (tester) async {
        await _fix(tester, 'https://www.tiktok.com/@cooking/video/7436123456789012345?is_from_webapp=1&sender_device=pc');
      });
      await _shot(tester, '$formName-platforms', size, ratio, _store(), _phoneShell, then: (tester) async {
        await tester.scrollUntilVisible(find.text('Supported Platforms'), 300, scrollable: find.byType(Scrollable).first);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
      });
      await _shot(tester, '$formName-history', size, ratio, _store(), _phoneShell, then: (tester) async {
        AppNav.showPage('history');
      });
      await _shot(tester, '$formName-sync', size, ratio, _store(), _phoneShell, then: (tester) async {
        SyncController.I.preview('KX7PQ3');
        AppNav.showPage('sync');
      });
      await _shot(tester, '$formName-look', size, ratio, _store(look: 'uwu', colour: 'not-green-4'), _phoneShell, then: (tester) async {
        AppNav.showPage('look');
      });
      await _shot(tester, '$formName-quick', size, ratio, _store(), () {
        Native.fake(const ['share', 'paste', 'open'], _noAnswer);
        // The quick screen, for text highlighted in a chat: "lol https://www.reddit.com/..."
        return const _QuickPreview();
      });
      await _shot(tester, '$formName-tour', size, ratio, {..._store(), 'tour.welcome': 'no'}, _phoneShell, then: _tourSecondStep);
    }, skip: _shotsWanted == null);
  }

  testWidgets('desktop screens', timeout: _shotTimeout, (tester) async {
    const size = Size(1440, 900);
    await _shot(tester, 'desktop-split', size, 2, _store(look: 'uwu'), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
      await _fix(tester, 'https://www.reddit.com/r/singapore/comments/1gq2abc/hawker_tips/?share_id=Xy7&utm_medium=android_app');
    });
    await _shot(tester, 'desktop-you', size, 2, _store(look: 'you'), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
      await _fix(tester, 'https://www.instagram.com/reel/C9xYz12AbCd/?igsh=MWZ0cnBhZ2lzNWh5bg==&utm_source=ig_web_copy_link');
    });
    await _shot(tester, 'desktop-dark', size, 2, _store(look: 'uwu', mode: 'dark', colour: 'not-green-1'), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
      await _fix(tester, 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=a1b2c3');
    });
    await _shot(tester, 'desktop-sync', size, 2, _store(look: 'uwu'), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
      SyncController.I.preview('KX7PQ3');
      AppNav.showPage('sync');
    });
    await _shot(tester, 'desktop-look', size, 2, _store(look: 'uwu', colour: 'not-green-3'), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
      AppNav.showPage('look');
    });
    await _shot(tester, 'desktop-command', size, 2, _store(look: 'uwu'), _desktopShell, padding: EdgeInsets.zero, then: _typeCommand);
    await _shot(tester, 'desktop-tour', size, 2, {..._store(look: 'uwu'), 'tour.welcome': 'no'}, _desktopShell, padding: EdgeInsets.zero, then: _tourSecondStep);
    await _shot(tester, 'desktop-platforms', size, 2, _store(look: 'you'), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
      await tester.scrollUntilVisible(find.text('Supported Platforms'), 300, scrollable: find.byType(Scrollable).last);
    });
  }, skip: _shotsWanted == null);

  // The desktop apps' own glass looks, Fluent 2, macOS Tahoe and Frosted Glass, over the backdrop
  // they draw where the system draws none, with each one's own accent: for checking by eye, not
  // for the store (Play's desktop pictures are of the Android app on a Chromebook).
  testWidgets('glass screens', timeout: const Timeout(Duration(minutes: 8)), (tester) async {
    const size = Size(1440, 900);
    addTearDown(() {
      Glass.override = null;
    });
    Future<void> ownAccent(WidgetTester tester) async {
      AppLook.I.systemAccent = null;
      AppLook.I.refresh();
      await _settle(tester, 4);
    }

    for (final glassLook in Glass.values) {
      Glass.override = glassLook;
      for (final mode in const ['light', 'dark']) {
        await _shot(tester, 'glass-${glassLook.name}-$mode', size, 2, _store(look: 'glass', mode: mode), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
          await ownAccent(tester);
          await _fix(tester, 'https://www.reddit.com/r/singapore/comments/1gq2abc/hawker_tips/?share_id=Xy7&utm_medium=android_app');
        });
      }
      await _shot(tester, 'glass-${glassLook.name}-look', size, 2, _store(look: 'glass'), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
        await ownAccent(tester);
        AppNav.showPage('look');
      });
      await _shot(tester, 'glass-${glassLook.name}-command', size, 2, _store(look: 'glass', mode: 'dark'), _desktopShell, padding: EdgeInsets.zero, then: (tester) async {
        await ownAccent(tester);
        await _typeCommand(tester);
      });
    }
  }, skip: _shotsWanted == null);
}

/// The quick screen over a chat, as Android shows it for "Fix link".
class _QuickPreview extends StatelessWidget {
  const _QuickPreview();

  @override
  Widget build(BuildContext context) {
    Native.fake(const ['share', 'paste', 'open'], _noAnswer);
    return const _QuickHost();
  }
}

class _QuickHost extends StatefulWidget {
  const _QuickHost();
  @override
  State<_QuickHost> createState() {
    return _QuickHostState();
  }
}

class _QuickHostState extends State<_QuickHost> {
  @override
  void initState() {
    super.initState();
    // What FixupPlugin.info's "quick" says for text highlighted in a box you can type in.
    Native.emit('Fixup', 'quick', {'from': 'select', 'replace': true, 'text': 'lol look https://www.reddit.com/r/singapore/comments/1gq2abc/hawker_tips/?share_id=Xy7&utm_medium=android_app'});
  }

  @override
  Widget build(BuildContext context) {
    return const QuickScreen();
  }
}

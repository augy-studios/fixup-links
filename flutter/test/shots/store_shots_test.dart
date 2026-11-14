// The app's screens for the Google Play listing's pictures (docs/store-assets/, tool/store_assets.mjs
// frames them), rendered by Flutter's test renderer from fixed data with the app's real fonts, so
// they come out the same whenever they're taken. As sgbus-timings' test/shots/.
//
//   SHOTS=all flutter test test/shots/            every shot, into build/shots/
//   SHOTS=phone-home,desktop flutter test test/shots/   only those (by the start of their names)
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

final _only = Platform.environment['SHOTS'];
final _out = Directory('build/shots');

bool _want(String name) {
  final only = _only;
  return only == null || only.isEmpty || only == 'all' || only.split(',').any((p) => name.startsWith(p));
}

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> _fonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']}/flutter';
  final mf = '$root/bin/cache/artifacts/material_fonts';
  final roboto = ['$mf/roboto-regular.ttf', '$mf/roboto-medium.ttf', '$mf/roboto-bold.ttf', '$mf/roboto-light.ttf'];
  await _font('Jua', ['assets/fonts/Jua-Regular.ttf']);
  await _font('Roboto', roboto);
  await _font('FlutterTest', roboto);
  await _font('MaterialIcons', ['$mf/materialicons-regular.otf']);
  // What a device falls back to for characters Jua hasn't, and emoji: Windows' own stand in.
  if (File('C:/Windows/Fonts/segoeui.ttf').existsSync()) await _font('Segoe UI', ['C:/Windows/Fonts/segoeui.ttf']);
  if (File('C:/Windows/Fonts/seguiemj.ttf').existsSync()) await _font('Segoe UI Emoji', ['C:/Windows/Fonts/seguiemj.ttf']);
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

Map<String, String> _store({String look = 'you', String mode = 'light', String colour = 'classic'}) {
  final items = [
    for (var i = 0; i < _links.length; i++)
      {
        'id': _now.millisecondsSinceEpoch - i * 3600 * 1000 * 5,
        'original': _links[i]['o'],
        'cleaned': _links[i]['c'],
        'platform': _links[i]['p'],
        'title': _links[i]['t'],
        'date': isoMs(_now.subtract(Duration(hours: i * 5 + (i > 3 ? 30 : 0)))),
      },
  ];
  return {
    'tour.welcome': 'done',
    'tour.pages': '["history","sync","look"]',
    historyKey: _encode(items),
    'uwufix.look': look,
    'uwufix.mode': mode,
    'uwufix.colorTheme': colour,
  };
}

String _encode(Object v) => const JsonCodecLite().encode(v);

class JsonCodecLite {
  const JsonCodecLite();
  String encode(Object v) => _enc(v);
  String _enc(Object? v) {
    if (v == null) return 'null';
    if (v is num || v is bool) return '$v';
    if (v is String) return '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    if (v is List) return '[${v.map(_enc).join(',')}]';
    if (v is Map) return '{${v.entries.map((e) => '${_enc('${e.key}')}:${_enc(e.value)}').join(',')}}';
    return '"$v"';
  }
}

Future<void> _settle(WidgetTester t, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// One shot: [build] in the app, at [size] logical pixels and [ratio], into build/shots/NAME.png.
Future<void> _shot(WidgetTester t, String name, Size size, double ratio, Map<String, String> store, Widget Function() build,
    {Future<void> Function(WidgetTester t)? then, EdgeInsets padding = const EdgeInsets.only(top: 28, bottom: 18)}) async {
  if (!_want(name)) return;
  Store.memory(store);
  AppNav.page.value = 'home';
  Fixer.I.clear();
  AppLook.now = () => DateTime(2026, 11, 14, 12, 30);
  // Material You's colours from a green wallpaper, as a phone would have them.
  AppLook.I.phoneLight = ColorScheme.fromSeed(seedColor: const Color(0xFF3F7D4B));
  AppLook.I.phoneDark = ColorScheme.fromSeed(seedColor: const Color(0xFF3F7D4B), brightness: Brightness.dark);
  AppLook.I.systemAccent = const Color(0xFF2E7D5B);
  t.view.physicalSize = size * ratio;
  t.view.devicePixelRatio = ratio;
  t.view.padding = FakeViewPadding(top: padding.top * ratio, bottom: padding.bottom * ratio);
  addTearDown(t.view.reset);
  final key = GlobalKey();
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(RepaintBoundary(key: key, child: UwuFixApp(home: build())));
  await _settle(t);
  if (then != null) await then(t);
  await _settle(t);
  await t.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await _settle(t, 4);
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  _out.createSync(recursive: true);
  File('${_out.path}/$name.png').writeAsBytesSync(bytes!);
  // Where each marked thing is, as fractions of the screen, for the store pictures' arrows.
  final rects = {
    for (final e in TourTarget.allRects().entries)
      e.key: [e.value.left / size.width, e.value.top / size.height, e.value.right / size.width, e.value.bottom / size.height],
  };
  File('${_out.path}/$name.json').writeAsStringSync(_encode(rects));
}

Future<void> _fix(WidgetTester t, String link) async {
  await t.runAsync(() => Fixer.I.fix(link));
  // Fixing puts it in the history; the history shown stays Sam's.
}

const _t = Timeout(Duration(minutes: 4));

void main() {
  setUpAll(() async {
    await _fonts();
    Api.fake = (_) async => null;
    Native.fake(const ['share', 'paste', 'open', 'push', 'update', 'checkupdate'], (_, _, _) async => null);
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

  for (final f in forms.entries) {
    final (size, ratio) = f.value;
    final p = f.key;
    testWidgets('$p screens', timeout: _t, (t) async {
      await _shot(t, '$p-home', size, ratio, _store(), () => const PhoneShell(), then: (t) async {
        await _fix(t, 'https://www.instagram.com/reel/C9xYz12AbCd/?igsh=MWZ0cnBhZ2lzNWh5bg==&utm_source=ig_web_copy_link');
      });
      await _shot(t, '$p-home-uwu', size, ratio, _store(look: 'uwu', colour: 'classic'), () => const PhoneShell(), then: (t) async {
        await _fix(t, 'https://x.com/uwuapps/status/1856001234567890123?s=46&t=Zq1x');
      });
      await _shot(t, '$p-home-dark', size, ratio, _store(look: 'uwu', mode: 'dark', colour: 'not-green-2'), () => const PhoneShell(), then: (t) async {
        await _fix(t, 'https://www.tiktok.com/@cooking/video/7436123456789012345?is_from_webapp=1&sender_device=pc');
      });
      await _shot(t, '$p-platforms', size, ratio, _store(), () => const PhoneShell(), then: (t) async {
        await t.scrollUntilVisible(find.text('Supported Platforms'), 300, scrollable: find.byType(Scrollable).first);
        await t.drag(find.byType(Scrollable).first, const Offset(0, -120));
      });
      await _shot(t, '$p-history', size, ratio, _store(), () => const PhoneShell(), then: (t) async => AppNav.showPage('history'));
      await _shot(t, '$p-sync', size, ratio, _store(), () => const PhoneShell(), then: (t) async {
        SyncController.I.preview('KX7PQ3');
        AppNav.showPage('sync');
      });
      await _shot(t, '$p-look', size, ratio, _store(look: 'uwu', colour: 'not-green-4'), () => const PhoneShell(), then: (t) async => AppNav.showPage('look'));
      await _shot(t, '$p-quick', size, ratio, _store(), () {
        Native.fake(const ['share', 'paste', 'open'], (_, _, _) async => null);
        // The quick screen, for text highlighted in a chat: "lol https://www.reddit.com/..."
        return const _QuickPreview();
      });
      await _shot(t, '$p-tour', size, ratio, {..._store(), 'tour.welcome': 'no'}, () => const PhoneShell(), then: (t) async {
        Tours.enabled = true;
        Tours.resetForTests();
        Tours.start_('home');
        await t.pump(const Duration(seconds: 1));
        await _settle(t, 10);
        await t.tap(find.widgetWithText(FilledButton, 'Next'));
        await _settle(t, 12);
        Tours.enabled = false;
      });
    }, skip: _only == null);
  }

  testWidgets('desktop screens', timeout: _t, (t) async {
    const size = Size(1440, 900);
    await _shot(t, 'desktop-split', size, 2, _store(look: 'uwu'), () => const DesktopShell(), padding: EdgeInsets.zero, then: (t) async {
      await _fix(t, 'https://www.reddit.com/r/singapore/comments/1gq2abc/hawker_tips/?share_id=Xy7&utm_medium=android_app');
    });
    await _shot(t, 'desktop-you', size, 2, _store(look: 'you'), () => const DesktopShell(), padding: EdgeInsets.zero, then: (t) async {
      await _fix(t, 'https://www.instagram.com/reel/C9xYz12AbCd/?igsh=MWZ0cnBhZ2lzNWh5bg==&utm_source=ig_web_copy_link');
    });
    await _shot(t, 'desktop-dark', size, 2, _store(look: 'uwu', mode: 'dark', colour: 'not-green-1'), () => const DesktopShell(), padding: EdgeInsets.zero, then: (t) async {
      await _fix(t, 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=a1b2c3');
    });
    await _shot(t, 'desktop-sync', size, 2, _store(look: 'uwu'), () => const DesktopShell(), padding: EdgeInsets.zero, then: (t) async {
      SyncController.I.preview('KX7PQ3');
      AppNav.showPage('sync');
    });
    await _shot(t, 'desktop-look', size, 2, _store(look: 'uwu', colour: 'not-green-3'), () => const DesktopShell(), padding: EdgeInsets.zero, then: (t) async => AppNav.showPage('look'));
    await _shot(t, 'desktop-command', size, 2, _store(look: 'uwu'), () => const DesktopShell(), padding: EdgeInsets.zero, then: (t) async {
      await t.tap(find.byType(TextField).first);
      await _settle(t, 4);
      await t.enterText(find.byType(TextField).first, 'red');
    });
    await _shot(t, 'desktop-tour', size, 2, {..._store(look: 'uwu'), 'tour.welcome': 'no'}, () => const DesktopShell(), padding: EdgeInsets.zero, then: (t) async {
      Tours.enabled = true;
      Tours.resetForTests();
      Tours.start_('home');
      await t.pump(const Duration(seconds: 1));
      await _settle(t, 10);
      await t.tap(find.widgetWithText(FilledButton, 'Next'));
      await _settle(t, 12);
      Tours.enabled = false;
    });
    await _shot(t, 'desktop-platforms', size, 2, _store(look: 'you'), () => const DesktopShell(), padding: EdgeInsets.zero, then: (t) async {
      await t.scrollUntilVisible(find.text('Supported Platforms'), 300, scrollable: find.byType(Scrollable).last);
    });
  }, skip: _only == null);
}

/// The quick screen over a chat, as Android shows it for "Fix link".
class _QuickPreview extends StatelessWidget {
  const _QuickPreview();

  @override
  Widget build(BuildContext context) {
    Native.fake(const ['share', 'paste', 'open'], (plugin, method, _) async => null);
    return const _QuickHost();
  }
}

class _QuickHost extends StatefulWidget {
  const _QuickHost();
  @override
  State<_QuickHost> createState() => _QuickHostState();
}

class _QuickHostState extends State<_QuickHost> {
  @override
  void initState() {
    super.initState();
    // What FixupPlugin.info's "quick" says for text highlighted in a box you can type in.
    Native.emit('Fixup', 'quick', {'from': 'select', 'replace': true, 'text': 'lol look https://www.reddit.com/r/singapore/comments/1gq2abc/hawker_tips/?share_id=Xy7&utm_medium=android_app'});
  }

  @override
  Widget build(BuildContext context) => const QuickScreen();
}

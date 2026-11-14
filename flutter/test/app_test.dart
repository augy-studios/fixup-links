// The app's screens in Flutter's test renderer: cleaning a link on the home page, the history,
// Look, and a page tour staying on screen and scrolling to what it lights, on a small phone and a
// big screen. Report a bug: sent with its ID, the draft kept, and Screenshot a page's button.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_test/flutter_test.dart';
import 'package:uwufix/api/resolve.dart';
import 'package:uwufix/app/app.dart';
import 'package:uwufix/app/nav.dart';
import 'package:uwufix/app/shell.dart';
import 'package:uwufix/data/history.dart';
import 'package:uwufix/data/store.dart';
import 'package:uwufix/features/bug/bug_report.dart';
import 'package:uwufix/features/home/fixer.dart';
import 'package:uwufix/features/tour/tour.dart';
import 'package:uwufix/native/native_bridge.dart';

Future<void> _app(WidgetTester t, {Size size = const Size(412, 892), Map<String, String> store = const {}}) async {
  Store.memory({...store});
  Native.fake(const ['share', 'paste', 'open'], (_, _, _) async => null);
  Api.fake = (_) async => null;
  Fixer.I.clear();
  AppNav.page.value = 'home';
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(const UwuFixApp(home: PhoneShell()));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('cleans a link and keeps it in the history', (t) async {
    await _app(t, store: {'tour.welcome': 'done'});
    await t.enterText(find.byType(TextField).first, 'https://x.com/someone/status/42?s=20&t=abc');
    await t.tap(find.text('Clean URL'));
    await t.pumpAndSettle();
    expect(find.text('https://fixupx.com/i/status/42'), findsOneWidget);
    expect(find.text('Removed 2 trackers'), findsOneWidget);
    expect(History.load().single.cleaned, 'https://fixupx.com/i/status/42');
  });

  testWidgets('an empty box says so', (t) async {
    await _app(t, store: {'tour.welcome': 'done'});
    await t.tap(find.text('Clean URL'));
    await t.pumpAndSettle();
    expect(find.text('Please enter a URL first.'), findsOneWidget);
  });

  testWidgets('History lists what was cleaned, and the bin deletes it', (t) async {
    await _app(t, store: {'tour.welcome': 'done', 'tour.pages': '["history"]'});
    History.add('https://www.reddit.com/r/a/?share_id=1', 'https://www.vxreddit.com/r/a/', 'Reddit', title: 'A thread');
    AppNav.showPage('history');
    await t.pumpAndSettle();
    expect(find.text('A thread'), findsOneWidget);
    await t.tap(find.byTooltip('Delete entry'));
    await t.pumpAndSettle();
    expect(find.text('No history yet. Clean a URL to get started.'), findsOneWidget);
  });

  for (final size in const [Size(320, 568), Size(412, 892), Size(1280, 800)]) {
    testWidgets('the welcome tour stays on screen at ${size.width.toInt()}x${size.height.toInt()}', (t) async {
      await _app(t, size: size);
      // A result, so the step about its buttons shows, low on a small screen.
      Fixer.I.input.text = 'https://youtu.be/abc?si=x';
      await Fixer.I.fix();
      await t.pumpAndSettle();
      Tours.start_('home');
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      final steps = Tours.steps['home']!;
      var seen = 0;
      while (true) {
        seen++;
        // The card's text, and the Next or Done button, are inside the screen.
        for (final label in ['Next', 'Done']) {
          final f = find.widgetWithText(FilledButton, label);
          if (f.evaluate().isEmpty) continue;
          final r = t.getRect(f);
          expect(r.left >= 0 && r.top >= 0 && r.right <= size.width && r.bottom <= size.height, isTrue, reason: 'step $seen: $label at $r');
        }
        final text = find.byWidgetPredicate((w) => w is Text && steps.any((s) => s.text() == w.data));
        expect(text, findsOneWidget, reason: 'step $seen shows its line');
        final tr = t.getRect(text);
        expect(tr.top >= 0 && tr.bottom <= size.height && tr.left >= 0 && tr.right <= size.width, isTrue, reason: 'step $seen text at $tr');
        if (find.widgetWithText(FilledButton, 'Done').evaluate().isNotEmpty) {
          await t.tap(find.widgetWithText(FilledButton, 'Done'));
          await t.pumpAndSettle();
          break;
        }
        await t.tap(find.widgetWithText(FilledButton, 'Next'));
        await t.pumpAndSettle();
      }
      expect(seen, greaterThanOrEqualTo(4));
      expect(Store.I.get('tour.welcome'), 'done');
    });
  }

  testWidgets('Skip ends a tour, and it counts as seen', (t) async {
    await _app(t);
    Tours.start_('home');
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(find.text('Skip'), findsNothing);
    expect(Tours.seen('home'), isTrue);
  });

  testWidgets('Look switches between Material You and the UwU Apps look', (t) async {
    await _app(t, store: {'tour.welcome': 'done', 'tour.pages': '["look"]'});
    AppNav.showPage('look');
    await t.pumpAndSettle();
    await t.tap(find.text('UwU Apps'));
    await t.pumpAndSettle();
    expect(Store.I.get('uwufix.look'), 'uwu');
    await t.tap(find.text('Dark'));
    await t.pumpAndSettle();
    expect(Store.I.get('uwufix.mode'), 'dark');
  });

  testWidgets('Report a bug sends the report and says its ID', (t) async {
    await _app(t, store: {'tour.welcome': 'done'});
    Map<String, dynamic>? sent;
    Api.fakePost = (path, body) async {
      sent = {'path': path, ...body};
      return {'id': '20261114-K7QM'};
    };
    addTearDown(() => Api.fakePost = null);
    await t.tap(find.byTooltip('Report a bug'));
    await t.pumpAndSettle();
    expect(find.text('Report a bug'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('bug.send')));
    await t.pumpAndSettle();
    expect(find.text('Please say what went wrong first.'), findsOneWidget);
    expect(sent, isNull);
    await t.enterText(find.byKey(const ValueKey('bug.text')), 'The Fix button does nothing.');
    await t.enterText(find.byKey(const ValueKey('bug.contact')), '@someone');
    // What's typed is kept until it's sent.
    expect(Store.I.get(BugReport.draftKey), contains('does nothing'));
    await t.tap(find.byKey(const ValueKey('bug.send')));
    await t.pumpAndSettle();
    expect(find.text('Sent as report 20261114-K7QM. Thank you! Augy will look into it.'), findsOneWidget);
    expect(sent!['path'], '/api/bug-report');
    expect(sent!['text'], 'The Fix button does nothing.');
    expect(sent!['contact'], '@someone');
    expect(sent!['platform'], 'android');
    expect(sent!['page'], 'Home');
    expect(sent!['website'], '');
    expect(Store.I.get(BugReport.draftKey), isNull);
  });

  testWidgets('Screenshot a page leaves the report for the app, and Cancel comes back', (t) async {
    await _app(t, store: {'tour.welcome': 'done', 'tour.pages': '["history"]'});
    await t.tap(find.byTooltip('Report a bug'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('bug.text')), 'History looks wrong.');
    await t.tap(find.byKey(const ValueKey('bug.screenshot')));
    await t.pumpAndSettle();
    expect(find.text('Screenshot this page'), findsOneWidget);
    expect(find.byKey(const ValueKey('bug.text')), findsNothing);
    AppNav.showPage('history');
    await t.pumpAndSettle();
    expect(find.text('Screenshot this page'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Screenshot this page'), findsNothing);
    expect(find.text('History looks wrong.'), findsOneWidget);
  });

  test('a whole page is made a JPEG Telegram takes as a photo', () {
    final tall = img.Image(width: 1200, height: 30000);
    img.fill(tall, color: img.ColorRgb8(240, 200, 220));
    final url = BugReport.pageJpeg(Uint8List.fromList(img.encodePng(tall)))!;
    expect(url, startsWith('data:image/jpeg;base64,'));
    final out = img.decodeJpg(UriData.parse(url).contentAsBytes())!;
    expect(out.width <= BugReport.pageWidth, isTrue);
    expect(out.height <= out.width * BugReport.pageRatio, isTrue);
    expect(out.width + out.height <= BugReport.pageSum, isTrue);
  });
}

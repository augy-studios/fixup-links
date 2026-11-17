// The app's screens in Flutter's test renderer: cleaning a link on the home page, the history,
// Look, and a page tour staying on screen and scrolling to what it lights, on a small phone and a
// big screen. Report a bug: sent with its ID, the draft kept, and Screenshot a page's button.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
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
import 'package:uwufix/theme/theme.dart';
import 'package:uwufix/widgets/glass.dart';

/// Starts the phone app on a fresh in-memory store with these values, at [size], with no device
/// and no network behind it.
Future<void> _startApp(WidgetTester tester, {Size size = const Size(412, 892), Map<String, String> store = const {}}) async {
  Store.memory({...store});
  Native.fake(const ['share', 'paste', 'open'], (_, _, _) async {
    return null;
  });
  Api.fake = (_) async {
    return null;
  };
  Fixer.I.clear();
  AppNav.page.value = 'home';
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const UwuFixApp(home: PhoneShell()));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cleans a link and keeps it in the history', (tester) async {
    await _startApp(tester, store: {'tour.welcome': 'done'});
    await tester.enterText(find.byType(TextField).first, 'https://x.com/someone/status/42?s=20&t=abc');
    await tester.tap(find.text('Clean URL'));
    await tester.pumpAndSettle();
    expect(find.text('https://fixupx.com/i/status/42'), findsOneWidget);
    expect(find.text('Removed 2 trackers'), findsOneWidget);
    expect(History.load().single.cleaned, 'https://fixupx.com/i/status/42');
  });

  testWidgets('an empty box says so', (tester) async {
    await _startApp(tester, store: {'tour.welcome': 'done'});
    await tester.tap(find.text('Clean URL'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a URL first.'), findsOneWidget);
  });

  testWidgets('History lists what was cleaned, and the bin deletes it', (tester) async {
    await _startApp(tester, store: {'tour.welcome': 'done', 'tour.pages': '["history"]'});
    History.add('https://www.reddit.com/r/a/?share_id=1', 'https://www.vxreddit.com/r/a/', 'Reddit', title: 'A thread');
    AppNav.showPage('history');
    await tester.pumpAndSettle();
    expect(find.text('A thread'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete entry'));
    await tester.pumpAndSettle();
    expect(find.text('No history yet. Clean a URL to get started.'), findsOneWidget);
  });

  for (final size in const [Size(320, 568), Size(412, 892), Size(1280, 800)]) {
    testWidgets('the welcome tour stays on screen at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await _startApp(tester, size: size);
      // A result, so the step about its buttons shows, low on a small screen.
      Fixer.I.input.text = 'https://youtu.be/abc?si=x';
      await Fixer.I.fix();
      await tester.pumpAndSettle();
      Tours.start_('home');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final steps = Tours.steps['home']!;
      var seen = 0;
      while (true) {
        seen++;
        // The card's text, and the Next or Done button, are inside the screen.
        for (final label in ['Next', 'Done']) {
          final buttonFinder = find.widgetWithText(FilledButton, label);
          if (buttonFinder.evaluate().isEmpty) {
            continue;
          }
          final buttonRect = tester.getRect(buttonFinder);
          final buttonOnScreen = buttonRect.left >= 0 && buttonRect.top >= 0 && buttonRect.right <= size.width && buttonRect.bottom <= size.height;
          expect(buttonOnScreen, isTrue, reason: 'step $seen: $label at $buttonRect');
        }
        final text = find.byWidgetPredicate((widget) {
          if (widget is! Text) {
            return false;
          }
          for (final step in steps) {
            if (step.text() == widget.data) {
              return true;
            }
          }
          return false;
        });
        expect(text, findsOneWidget, reason: 'step $seen shows its line');
        final textRect = tester.getRect(text);
        final textOnScreen = textRect.top >= 0 && textRect.bottom <= size.height && textRect.left >= 0 && textRect.right <= size.width;
        expect(textOnScreen, isTrue, reason: 'step $seen text at $textRect');
        if (find.widgetWithText(FilledButton, 'Done').evaluate().isNotEmpty) {
          await tester.tap(find.widgetWithText(FilledButton, 'Done'));
          await tester.pumpAndSettle();
          break;
        }
        await tester.tap(find.widgetWithText(FilledButton, 'Next'));
        await tester.pumpAndSettle();
      }
      expect(seen, greaterThanOrEqualTo(4));
      expect(Store.I.get('tour.welcome'), 'done');
    });
  }

  testWidgets('Skip ends a tour, and it counts as seen', (tester) async {
    await _startApp(tester);
    Tours.start_('home');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Skip'), findsNothing);
    expect(Tours.seen('home'), isTrue);
  });

  testWidgets('Look switches between Material You and the UwU Apps look', (tester) async {
    await _startApp(tester, store: {'tour.welcome': 'done', 'tour.pages': '["look"]'});
    AppNav.showPage('look');
    await tester.pumpAndSettle();
    await tester.tap(find.text('UwU Apps'));
    await tester.pumpAndSettle();
    expect(Store.I.get('uwufix.look'), 'uwu');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Store.I.get('uwufix.mode'), 'dark');
  });

  group('a desktop\'s glass in place of Material You', () {
    tearDown(() {
      Glass.override = null;
      AppLook.I.backdrop = false;
    });

    for (final (glass, name) in const [(Glass.fluent, 'Fluent 2'), (Glass.tahoe, 'macOS Tahoe'), (Glass.frosted, 'Frosted Glass')]) {
      testWidgets('Look offers $name and UwU Apps', (tester) async {
        Glass.override = glass;
        await _startApp(tester, store: {'tour.welcome': 'done', 'tour.pages': '["look"]', 'uwufix.look': 'uwu'});
        AppNav.showPage('look');
        await tester.pumpAndSettle();
        expect(find.text('Material You'), findsNothing);
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
        expect(Store.I.get('uwufix.look'), 'glass');
        final themeColors = Theme.of(tester.element(find.text(name))).extension<Fx>()!;
        expect(themeColors.glass, glass);
        expect(themeColors.uwu, isFalse);
        // The glass's own backdrop behind it, until the system draws one.
        expect(find.byType(GlassBackdrop), findsOneWidget);
        expect(find.byType(GlassPane), findsWidgets);
      });
    }

    testWidgets('a computer reads Material You from before as its glass, and a phone reads glass as Material You', (tester) async {
      Glass.override = Glass.tahoe;
      Store.memory({'uwufix.look': 'you'});
      expect(AppLook.I.glass, Glass.tahoe);
      expect(AppLook.I.materialYou, isFalse);
      Glass.override = null;
      Store.memory({'uwufix.look': 'glass'});
      expect(AppLook.I.materialYou, isTrue);
      expect(AppLook.I.glass, isNull);
    });

    testWidgets('over the system\'s backdrop the window is left clear', (tester) async {
      Glass.override = Glass.fluent;
      await _startApp(tester, store: {'tour.welcome': 'done', 'uwufix.look': 'glass'});
      final context = tester.element(find.byType(PhoneShell));
      expect(Theme.of(context).scaffoldBackgroundColor.a, 0);
      AppLook.I.backdrop = true;
      await tester.pumpAndSettle();
      // Mica is tinted already: no veil over it.
      final veil = tester.widget<ColoredBox>(find.descendant(of: find.byType(GlassBackdrop), matching: find.byType(ColoredBox)).first);
      expect(veil.color.a, 0);
    });
  });

  testWidgets('Report a bug sends the report and says its ID', (tester) async {
    await _startApp(tester, store: {'tour.welcome': 'done'});
    Map<String, dynamic>? sent;
    Api.fakePost = (path, body) async {
      sent = {'path': path, ...body};
      return {'id': '20261114-K7QM'};
    };
    addTearDown(() {
      Api.fakePost = null;
    });
    await tester.tap(find.byTooltip('Report a bug'));
    await tester.pumpAndSettle();
    expect(find.text('Report a bug'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('bug.send')));
    await tester.pumpAndSettle();
    expect(find.text('Please say what went wrong first.'), findsOneWidget);
    expect(sent, isNull);
    await tester.enterText(find.byKey(const ValueKey('bug.text')), 'The Fix button does nothing.');
    await tester.enterText(find.byKey(const ValueKey('bug.contact')), '@someone');
    // What's typed is kept until it's sent.
    expect(Store.I.get(BugReport.draftKey), contains('does nothing'));
    await tester.tap(find.byKey(const ValueKey('bug.send')));
    await tester.pumpAndSettle();
    expect(find.text('Sent as report 20261114-K7QM. Thank you! Augy will look into it.'), findsOneWidget);
    expect(sent!['path'], '/api/bug-report');
    expect(sent!['text'], 'The Fix button does nothing.');
    expect(sent!['contact'], '@someone');
    expect(sent!['platform'], 'android');
    expect(sent!['page'], 'Home');
    expect(sent!['website'], '');
    expect(Store.I.get(BugReport.draftKey), isNull);
  });

  testWidgets('Screenshot a page leaves the report for the app, and Cancel comes back', (tester) async {
    await _startApp(tester, store: {'tour.welcome': 'done', 'tour.pages': '["history"]'});
    await tester.tap(find.byTooltip('Report a bug'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bug.text')), 'History looks wrong.');
    await tester.tap(find.byKey(const ValueKey('bug.screenshot')));
    await tester.pumpAndSettle();
    expect(find.text('Screenshot this page'), findsOneWidget);
    expect(find.byKey(const ValueKey('bug.text')), findsNothing);
    AppNav.showPage('history');
    await tester.pumpAndSettle();
    expect(find.text('Screenshot this page'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Screenshot this page'), findsNothing);
    expect(find.text('History looks wrong.'), findsOneWidget);
  });

  test('a whole page is made a JPEG Telegram takes as a photo', () {
    final tall = image.Image(width: 1200, height: 30000);
    image.fill(tall, color: image.ColorRgb8(240, 200, 220));
    final url = BugReport.pageJpeg(Uint8List.fromList(image.encodePng(tall)))!;
    expect(url, startsWith('data:image/jpeg;base64,'));
    final decoded = image.decodeJpg(UriData.parse(url).contentAsBytes())!;
    expect(decoded.width <= BugReport.pageWidth, isTrue);
    expect(decoded.height <= decoded.width * BugReport.pageRatio, isTrue);
    expect(decoded.width + decoded.height <= BugReport.pageSum, isTrue);
  });
}

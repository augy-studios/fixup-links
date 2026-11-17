// The title bar's Screenshot and Long screenshot (docs/desktop-features-spec.md §5): a picture of
// the app's content (not the title bar), copied to the clipboard and saved in the Downloads folder
// as "uwuFix YYYY-MM-DD HH.MM.SS.png", with a notification that shows it in its folder when clicked.
//
// Long screenshot draws the whole page, top to bottom, not just what's on screen, up to 16384 px
// tall, by laying the page out again off screen at the window's width with no height limit
// ("... (long).png"). One screenshot at a time.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

import '../data/history.dart';
import '../features/history/history_page.dart';
import '../features/home/home_page.dart';
import '../theme/theme.dart';
import '../widgets/glass.dart';
import 'notify.dart';

bool _busy = false;

/// Takes one, and says how it went: "Screenshot copied and saved", or null if it couldn't.
Future<String?> takeScreenshot(GlobalKey content, {required String page, bool long = false}) async {
  if (_busy) {
    return null;
  }
  _busy = true;
  try {
    final contentContext = content.currentContext;
    if (contentContext == null) {
      return null;
    }
    final ratio = MediaQuery.devicePixelRatioOf(contentContext);
    final palette = contentContext.fx;
    ui.Image image;
    if (long && (page == 'home' || page == 'history')) {
      final box = contentContext.findRenderObject()! as RenderBox;
      Widget longPage;
      if (page == 'home') {
        longPage = const HomePage(long: true);
      } else {
        longPage = const _HistoryLong();
      }
      image = await _renderLong(contentContext, longPage, width: box.size.width, ratio: ratio);
    } else {
      final boundary = contentContext.findRenderObject()! as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: ratio);
    }
    if (palette.glass != null) {
      image = await flattenShot(image, palette.bg);
    }
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      return null;
    }
    final bytes = data.buffer.asUint8List();
    final downloads = await getDownloadsDirectory();
    Directory directory;
    if (downloads != null) {
      directory = downloads;
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    final now = DateTime.now();
    String twoDigits(int number) {
      return number.toString().padLeft(2, '0');
    }

    String longSuffix;
    String notificationTitle;
    if (long) {
      longSuffix = ' (long)';
      notificationTitle = 'Long screenshot saved';
    } else {
      longSuffix = '';
      notificationTitle = 'Screenshot saved';
    }
    final name = 'uwuFix ${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)} ${twoDigits(now.hour)}.${twoDigits(now.minute)}.${twoDigits(now.second)}$longSuffix.png';
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    try {
      await Pasteboard.writeImage(bytes);
    } catch (_) {}
    await DesktopNotify.show(notificationTitle, '$name, in Downloads and on the clipboard. Click to show it.', payload: 'file:${file.path}');
    return 'Screenshot copied and saved';
  } catch (_) {
    return null;
  } finally {
    _busy = false;
  }
}

/// [page] laid out off screen at [width], in a render tree of its own, as tall as it is (up to
/// 16384 px), and drawn.
Future<ui.Image> _renderLong(BuildContext context, Widget page, {required double width, required double ratio}) async {
  final theme = Theme.of(context);
  final media = MediaQuery.of(context);
  final view = View.of(context);
  await precacheImage(const AssetImage('assets/images/logo.png'), context);
  final maxHeight = 16384 / ratio;
  final repaint = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: repaint),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
      physicalConstraints: BoxConstraints(maxWidth: width * ratio, maxHeight: maxHeight * ratio),
      devicePixelRatio: ratio,
    ),
  );
  final pipeline = PipelineOwner();
  pipeline.rootNode = renderView;
  renderView.prepareInitialFrame();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaint,
    child: MediaQuery(
      data: media.copyWith(size: Size(width, maxHeight), padding: EdgeInsets.zero),
      child: Theme(
        data: theme,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: width,
            child: Material(color: theme.scaffoldBackgroundColor, child: page),
          ),
        ),
      ),
    ),
  ).attachToRenderTree(buildOwner);
  buildOwner.buildScope(root);
  buildOwner.finalizeTree();
  pipeline.flushLayout();
  pipeline.flushCompositingBits();
  pipeline.flushPaint();
  final image = await repaint.toImage(pixelRatio: ratio);
  return image;
}

/// The whole history, top to bottom, for a long screenshot.
class _HistoryLong extends StatelessWidget {
  const _HistoryLong();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('History', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final entry in History.load()) Padding(padding: const EdgeInsets.only(bottom: 8), child: historyRow(entry)),
      ]),
    );
  }
}

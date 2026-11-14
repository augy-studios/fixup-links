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
import 'notify.dart';

bool _busy = false;

/// Takes one, and says how it went: "Screenshot copied and saved", or null if it couldn't.
Future<String?> takeScreenshot(GlobalKey content, {required String page, bool long = false}) async {
  if (_busy) return null;
  _busy = true;
  try {
    final ctx = content.currentContext;
    if (ctx == null) return null;
    final ratio = MediaQuery.devicePixelRatioOf(ctx);
    ui.Image image;
    if (long && (page == 'home' || page == 'history')) {
      final box = ctx.findRenderObject()! as RenderBox;
      image = await _renderLong(ctx, page == 'home' ? const HomePage(long: true) : const _HistoryLong(), width: box.size.width, ratio: ratio);
    } else {
      final boundary = ctx.findRenderObject()! as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: ratio);
    }
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'uwuFix ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}.${two(t.second)}${long ? ' (long)' : ''}.png';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    try {
      await Pasteboard.writeImage(bytes);
    } catch (_) {}
    await DeskNotify.show(long ? 'Long screenshot saved' : 'Screenshot saved', '$name, in Downloads and on the clipboard. Click to show it.', payload: 'file:${file.path}');
    return 'Screenshot copied and saved';
  } catch (_) {
    return null;
  } finally {
    _busy = false;
  }
}

/// [page] laid out off screen at [width], as tall as it is (up to 16384 px), and drawn.
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
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final build = BuildOwner(focusManager: FocusManager());
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
  ).attachToRenderTree(build);
  build.buildScope(root);
  build.finalizeTree();
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('History', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final e in History.load()) Padding(padding: const EdgeInsets.only(bottom: 8), child: historyRow(e)),
        ]),
      );
}

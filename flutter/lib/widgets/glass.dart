// A desktop's glass, drawn (theme/theme.dart's Glass): the panes that sit on it, and what's behind
// them.
//
//   GlassPane       a pane of glass, as iOS's Liquid Glass has one: what's behind it blurred, a
//                   breath of white over that, light catching its top edge and a little of its
//                   bottom, and a hairline round it so it holds its shape on anything
//   GlassBackdrop   behind the whole app: a veil of the window's colour over the system's backdrop
//                   (Mica, the vibrancy, the compositor's blur) where it draws one, or otherwise
//                   a backdrop of the glass's own, soft washes of the accent, for the panes to blur
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// A pane of the look's glass. Only for a desktop's glass (context.fx.glass).
class GlassPane extends StatelessWidget {
  const GlassPane({super.key, required this.child, this.radius, this.color, this.blur = true});
  final Widget child;

  /// Its corners: the glass's card radius unless given.
  final double? radius;

  /// Its fill: the glass's pane colour unless given.
  final Color? color;

  /// Whether it blurs what's behind it. Off where only the window's clear backdrop is behind it,
  /// which the system has blurred already.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final g = fx.glass!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius ?? g.card);
    Widget pane = Material(
      color: color ?? fx.surface,
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: fx.border)),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _Sheen(r, g.edge, dark),
        foregroundPainter: _Rim(r, g.edge, dark),
        child: child,
      ),
    );
    if (blur) {
      pane = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: g.blur, sigmaY: g.blur), child: pane),
      );
    }
    return pane;
  }
}

/// The light on a pane: a soft wash down from its top, under what's on it.
class _Sheen extends CustomPainter {
  const _Sheen(this.radius, this.edge, this.dark);
  final BorderRadius radius;
  final double edge;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final a = (dark ? 0.07 : 0.22) * edge;
    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: a), Colors.white.withValues(alpha: 0)],
          stops: const [0, 0.45],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Sheen old) => old.radius != radius || old.edge != edge || old.dark != dark;
}

/// The rim where light catches a pane: bright along its top, fading round the sides, a little
/// again along its bottom.
class _Rim extends CustomPainter {
  const _Rim(this.radius, this.edge, this.dark);
  final BorderRadius radius;
  final double edge;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.75);
    final top = (dark ? 0.32 : 0.95) * edge;
    final bottom = (dark ? 0.12 : 0.45) * edge;
    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: top),
            Colors.white.withValues(alpha: top * 0.15),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: bottom),
          ],
          stops: const [0, 0.3, 0.7, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Rim old) => old.radius != radius || old.edge != edge || old.dark != dark;
}

/// Behind the app, in a desktop's glass: the system's backdrop with a veil over it, or the
/// glass's own. In any other look, just [child].
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child, this.opaque = false});
  final Widget child;

  /// Its own backdrop even where the system draws one: for pictures of the app.
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final g = fx.glass;
    if (g == null) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Widget behind = AppLook.I.backdrop && !opaque
        ? ColoredBox(color: fx.bg.withValues(alpha: g.veil))
        : CustomPaint(painter: _Washes(fx.bg, fx.brandInk, dark));
    return Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(child: RepaintBoundary(child: behind)),
      child,
    ]);
  }
}

/// The glass's own backdrop, where the system draws none: the window's colour with three soft
/// washes of the accent and its neighbours over it, as a wallpaper behind glass would be.
class _Washes extends CustomPainter {
  const _Washes(this.base, this.accent, this.dark);
  final Color base, accent;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = base);
    final hsl = HSLColor.fromColor(accent);
    final a = dark ? 0.26 : 0.30;
    final side = size.longestSide;
    void wash(Alignment at, double hueShift, double reach, double alpha) {
      final c = hsl.withHue((hsl.hue + hueShift) % 360).toColor();
      final centre = at.alongSize(size);
      final r = side * reach;
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: r)),
      );
    }

    wash(const Alignment(-0.9, -1), 0, 0.55, a);
    wash(const Alignment(1, -0.2), 40, 0.45, a * 0.8);
    wash(const Alignment(0.1, 1.1), -50, 0.5, a * 0.7);
  }

  @override
  bool shouldRepaint(_Washes old) => old.base != base || old.accent != accent || old.dark != dark;
}

/// A picture of the app laid on [color], for a desktop's glass: where the window is clear the
/// system's backdrop shows, and a picture has nothing behind it.
Future<ui.Image> flattenShot(ui.Image image, Color color) async {
  final record = ui.PictureRecorder();
  Canvas(record)
    ..drawColor(color.withValues(alpha: 1), BlendMode.src)
    ..drawImage(image, Offset.zero, Paint());
  final out = await record.endRecording().toImage(image.width, image.height);
  image.dispose();
  return out;
}

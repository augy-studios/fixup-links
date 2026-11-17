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
    final palette = context.fx;
    final glass = palette.glass!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    double cornerRadius = glass.card;
    final givenRadius = radius;
    if (givenRadius != null) {
      cornerRadius = givenRadius;
    }
    final borderRadius = BorderRadius.circular(cornerRadius);
    Color fillColor = palette.surface;
    final givenColor = color;
    if (givenColor != null) {
      fillColor = givenColor;
    }
    Widget pane = Material(
      color: fillColor,
      shape: RoundedRectangleBorder(borderRadius: borderRadius, side: BorderSide(color: palette.border)),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _Sheen(borderRadius, glass.edge, dark),
        foregroundPainter: _Rim(borderRadius, glass.edge, dark),
        child: child,
      ),
    );
    if (blur) {
      pane = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: glass.blur, sigmaY: glass.blur), child: pane),
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
    double strength;
    if (dark) {
      strength = 0.07;
    } else {
      strength = 0.22;
    }
    final alpha = strength * edge;
    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: alpha), Colors.white.withValues(alpha: 0)],
          stops: const [0, 0.45],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_Sheen oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.edge != edge || oldDelegate.dark != dark;
  }
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
    double topStrength;
    double bottomStrength;
    if (dark) {
      topStrength = 0.32;
      bottomStrength = 0.12;
    } else {
      topStrength = 0.95;
      bottomStrength = 0.45;
    }
    final top = topStrength * edge;
    final bottom = bottomStrength * edge;
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
  bool shouldRepaint(_Rim oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.edge != edge || oldDelegate.dark != dark;
  }
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
    final palette = context.fx;
    final glass = palette.glass;
    if (glass == null) {
      return child;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Widget behind;
    if (AppLook.I.backdrop && !opaque) {
      behind = ColoredBox(color: palette.bg.withValues(alpha: glass.veil));
    } else {
      behind = CustomPaint(painter: _Washes(palette.bg, palette.brandInk, dark));
    }
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
    double strength;
    if (dark) {
      strength = 0.26;
    } else {
      strength = 0.30;
    }
    final side = size.longestSide;

    // One soft round wash of the accent, its hue shifted, centred at [position].
    void wash(Alignment position, double hueShift, double reach, double alpha) {
      final washColor = hsl.withHue((hsl.hue + hueShift) % 360).toColor();
      final centre = position.alongSize(size);
      final washRadius = side * reach;
      canvas.drawCircle(
        centre,
        washRadius,
        Paint()
          ..shader = RadialGradient(
            colors: [washColor.withValues(alpha: alpha), washColor.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: washRadius)),
      );
    }

    wash(const Alignment(-0.9, -1), 0, 0.55, strength);
    wash(const Alignment(1, -0.2), 40, 0.45, strength * 0.8);
    wash(const Alignment(0.1, 1.1), -50, 0.5, strength * 0.7);
  }

  @override
  bool shouldRepaint(_Washes oldDelegate) {
    return oldDelegate.base != base || oldDelegate.accent != accent || oldDelegate.dark != dark;
  }
}

/// A picture of the app laid on [color], for a desktop's glass: where the window is clear the
/// system's backdrop shows, and a picture has nothing behind it.
Future<ui.Image> flattenShot(ui.Image image, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(color.withValues(alpha: 1), BlendMode.src);
  canvas.drawImage(image, Offset.zero, Paint());
  final flattened = await recorder.endRecording().toImage(image.width, image.height);
  image.dispose();
  return flattened;
}

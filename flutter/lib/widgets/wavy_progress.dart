// A progress bar as Material 3 Expressive draws one, the way Android's own updater and apps in
// Material You do: the part done as a wave in the theme's primary colour, drifting, then a gap and
// the rest of the way flat in its secondary container colour, with a dot at the end. With no
// telling how far it's got, a wavy stretch sweeps across instead.
//
// The same measures as the updates page's (android/.../WavyProgressView.java): a 4 dp line, waves
// 40 dp long and 3 dp high (half as long while sweeping), flat near the start and the end. With
// animations off it keeps still.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WavyProgress extends StatefulWidget {
  const WavyProgress({super.key, this.value, this.color, this.trackColor, this.semanticsLabel});

  /// From 0 to 1, or null while there's no telling.
  final double? value;
  final Color? color;
  final Color? trackColor;
  final String? semanticsLabel;

  @override
  State<WavyProgress> createState() => _WavyProgressState();
}

class _WavyProgressState extends State<WavyProgress> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  Duration _last = Duration.zero;
  double _shown = 0; // chases widget.value a little each frame, so small steps glide

  @override
  void initState() {
    super.initState();
    _shown = widget.value ?? 0;
    _ticker = createTicker((t) {
      final dt = (t - _last).inMicroseconds / 1000.0;
      _last = t;
      final target = widget.value ?? 0;
      final step = 1 - math.pow(0.8, dt / 30).toDouble();
      _shown += (target - _shown) * step.clamp(0.0, 1.0);
      if ((target - _shown).abs() < 0.001) _shown = target;
      setState(() => _elapsed = t);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = widget.value;
    final still = !_ticker.isActive;
    return Semantics(
      label: widget.semanticsLabel ?? 'Progress',
      value: value == null ? null : '${(value * 100).round()}%',
      child: SizedBox(
        height: 10,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavyPainter(
            progress: value == null ? null : (still ? value : _shown),
            ms: _elapsed.inMilliseconds,
            active: widget.color ?? scheme.primary,
            track: widget.trackColor ?? scheme.secondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _WavyPainter extends CustomPainter {
  _WavyPainter({required this.progress, required this.ms, required this.active, required this.track});
  final double? progress;
  final int ms;
  final Color active, track;

  static const thickness = 4.0, amplitude = 3.0, wavelength = 40.0, gap = 4.0;
  static const driftMs = 1000, sweepMs = 1800;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()
      ..color = active
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final t = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    final half = thickness / 2;
    final left = half, right = size.width - half, cy = size.height / 2;
    if (right <= left) return;
    final width = right - left;
    final phase = 2 * math.pi * (ms % driftMs) / driftMs;

    void wave(double from, double to, double amp, double len) {
      final path = Path();
      final step = math.max(1.0, len / 24);
      for (var x = from;; x = math.min(to, x + step)) {
        final y = cy + amp * math.sin(2 * math.pi * x / len - phase);
        if (x == from) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        if (x >= to) break;
      }
      canvas.drawPath(path, a);
    }

    final p = progress;
    if (p == null) {
      // A stretch 40% as long as the bar, easing in from the left and out past the right.
      final sweep = (ms % sweepMs) / sweepMs;
      final eased = 0.5 - math.cos(math.pi * sweep) / 2;
      final head = left + (width * 1.4) * eased;
      final tail = head - width * 0.4;
      final from = math.max(left, tail), to = math.min(right, head);
      if (to > from) wave(from, to, amplitude, wavelength / 2);
      if (from - gap - thickness > left) canvas.drawLine(Offset(left, cy), Offset(from - gap - thickness, cy), t);
      if (to + gap + thickness < right) canvas.drawLine(Offset(to + gap + thickness, cy), Offset(right, cy), t);
      return;
    }
    final end = left + width * p;
    // Flat at the very start and as it finishes, as Material's does.
    final amp = amplitude * math.max(0, math.min(1, math.min(p / 0.1, (1 - p) / 0.05)));
    if (end > left) wave(left, end, amp.toDouble(), wavelength);
    final trackFrom = p > 0 ? end + gap + thickness : left;
    if (trackFrom < right) canvas.drawLine(Offset(trackFrom, cy), Offset(right, cy), t);
    // The stop dot at the end, till the wave reaches it.
    if (p < 1) canvas.drawCircle(Offset(right, cy), half, Paint()..color = active);
  }

  @override
  bool shouldRepaint(_WavyPainter old) => old.progress != progress || old.ms != ms || old.active != active || old.track != track;
}

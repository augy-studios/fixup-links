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

/// A Material 3 Expressive progress bar: a drifting wave for the part done, or a sweeping wave
/// while there's no telling how far it's got.
class WavyProgress extends StatefulWidget {
  const WavyProgress({super.key, this.value, this.color, this.trackColor, this.semanticsLabel});

  /// From 0 to 1, or null while there's no telling.
  final double? value;
  final Color? color;
  final Color? trackColor;
  final String? semanticsLabel;

  @override
  State<WavyProgress> createState() {
    return _WavyProgressState();
  }
}

class _WavyProgressState extends State<WavyProgress> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  Duration _last = Duration.zero;
  double _shown = 0; // chases widget.value a little each frame, so small steps glide

  /// The progress asked for, or 0 while there's no telling.
  double _targetValue() {
    final value = widget.value;
    if (value == null) {
      return 0;
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    _shown = _targetValue();
    _ticker = createTicker((elapsed) {
      final millisecondsSinceLast = (elapsed - _last).inMicroseconds / 1000.0;
      _last = elapsed;
      final target = _targetValue();
      final step = 1 - math.pow(0.8, millisecondsSinceLast / 30).toDouble();
      _shown += (target - _shown) * step.clamp(0.0, 1.0);
      if ((target - _shown).abs() < 0.001) {
        _shown = target;
      }
      setState(() {
        _elapsed = elapsed;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var still = false;
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations;
    if (disableAnimations != null) {
      still = disableAnimations;
    }
    if (still && _ticker.isActive) {
      _ticker.stop();
    }
    if (!still && !_ticker.isActive) {
      _ticker.start();
    }
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

    String label = 'Progress';
    final givenLabel = widget.semanticsLabel;
    if (givenLabel != null) {
      label = givenLabel;
    }
    String? percentText;
    double? progress;
    if (value != null) {
      percentText = '${(value * 100).round()}%';
      if (still) {
        progress = value;
      } else {
        progress = _shown;
      }
    }
    Color activeColor = scheme.primary;
    final givenColor = widget.color;
    if (givenColor != null) {
      activeColor = givenColor;
    }
    Color trackColor = scheme.secondaryContainer;
    final givenTrackColor = widget.trackColor;
    if (givenTrackColor != null) {
      trackColor = givenTrackColor;
    }

    return Semantics(
      label: label,
      value: percentText,
      child: SizedBox(
        height: 10,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavyPainter(
            progress: progress,
            milliseconds: _elapsed.inMilliseconds,
            active: activeColor,
            track: trackColor,
          ),
        ),
      ),
    );
  }
}

/// Paints the bar: the wave for the part done (or the sweeping stretch), the flat track for the
/// rest, and the stop dot at the end.
class _WavyPainter extends CustomPainter {
  _WavyPainter({required this.progress, required this.milliseconds, required this.active, required this.track});
  final double? progress;
  final int milliseconds;
  final Color active, track;

  static const thickness = 4.0, amplitude = 3.0, wavelength = 40.0, gap = 4.0;
  static const driftMilliseconds = 1000, sweepMilliseconds = 1800;

  @override
  void paint(Canvas canvas, Size size) {
    final activePaint = Paint()
      ..color = active
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    final half = thickness / 2;
    final left = half, right = size.width - half, centreY = size.height / 2;
    if (right <= left) {
      return;
    }
    final width = right - left;
    final phase = 2 * math.pi * (milliseconds % driftMilliseconds) / driftMilliseconds;

    // A wave from x [from] to x [to], [waveAmplitude] high and [waveLength] long.
    void wave(double from, double to, double waveAmplitude, double waveLength) {
      final path = Path();
      final step = math.max(1.0, waveLength / 24);
      for (var pointX = from;; pointX = math.min(to, pointX + step)) {
        final pointY = centreY + waveAmplitude * math.sin(2 * math.pi * pointX / waveLength - phase);
        if (pointX == from) {
          path.moveTo(pointX, pointY);
        } else {
          path.lineTo(pointX, pointY);
        }
        if (pointX >= to) {
          break;
        }
      }
      canvas.drawPath(path, activePaint);
    }

    final shownProgress = progress;
    if (shownProgress == null) {
      // A stretch 40% as long as the bar, easing in from the left and out past the right.
      final sweep = (milliseconds % sweepMilliseconds) / sweepMilliseconds;
      final eased = 0.5 - math.cos(math.pi * sweep) / 2;
      final head = left + (width * 1.4) * eased;
      final tail = head - width * 0.4;
      final from = math.max(left, tail), to = math.min(right, head);
      if (to > from) {
        wave(from, to, amplitude, wavelength / 2);
      }
      if (from - gap - thickness > left) {
        canvas.drawLine(Offset(left, centreY), Offset(from - gap - thickness, centreY), trackPaint);
      }
      if (to + gap + thickness < right) {
        canvas.drawLine(Offset(to + gap + thickness, centreY), Offset(right, centreY), trackPaint);
      }
      return;
    }
    final end = left + width * shownProgress;
    // Flat at the very start and as it finishes, as Material's does.
    final waveAmplitude =
        amplitude * math.max(0, math.min(1, math.min(shownProgress / 0.1, (1 - shownProgress) / 0.05)));
    if (end > left) {
      wave(left, end, waveAmplitude.toDouble(), wavelength);
    }
    double trackFrom;
    if (shownProgress > 0) {
      trackFrom = end + gap + thickness;
    } else {
      trackFrom = left;
    }
    if (trackFrom < right) {
      canvas.drawLine(Offset(trackFrom, centreY), Offset(right, centreY), trackPaint);
    }
    // The stop dot at the end, till the wave reaches it.
    if (shownProgress < 1) {
      canvas.drawCircle(Offset(right, centreY), half, Paint()..color = active);
    }
  }

  @override
  bool shouldRepaint(_WavyPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.milliseconds != milliseconds ||
        oldDelegate.active != active ||
        oldDelegate.track != track;
  }
}

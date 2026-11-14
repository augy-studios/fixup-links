// Page tours (docs/page-tour-spec.md), as the site's js/tour.js: the first time a page is shown, it
// dims, one thing on it is lit, and a hand-drawn chalk arrow runs to it from a line saying what it
// does. Next moves on, Skip (or Escape) ends it. The home page's is the welcome, the first time the
// app opens. Show me around (the Edge Tray's, or the desktop's rail) has each again.
//
// A thing is marked with TourTarget(id: 'home.clean', child: ...). A step names its thing by id,
// alternatives allowed ('history.list|history.empty': the first on screen is lit), and a step
// whose thing isn't on screen is left out.
//
// Tours stay on screen: each thing is scrolled into view first (centred, or from its top if it's
// taller than 60% of the screen), the card goes on the side with room, narrowing or taking a
// backing of its own if it must, and every point of the arrow is kept inside the screen (§3).
//
// Seen: tour.welcome ("done", home's) and tour.pages (the others' ids), as the site keeps them.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/nav.dart';
import '../../data/store.dart';
import '../../theme/theme.dart';

/// Marks a widget as what a tour's step lights up.
class TourTarget extends StatefulWidget {
  const TourTarget({super.key, required this.id, required this.child});
  final String id;
  final Widget child;

  static final Map<String, List<GlobalKey>> _keys = {};

  static BuildContext? contextOf(String id) {
    for (final k in (_keys[id] ?? const <GlobalKey>[]).reversed) {
      final c = k.currentContext;
      if (c != null && rectOfContext(c) != null) return c;
    }
    return null;
  }

  static Rect? rectOfContext(BuildContext c) {
    final box = c.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize || box.size.isEmpty) return null;
    // Not offstage (a page of the desktop's stack that isn't on show, say).
    var hidden = false;
    c.visitAncestorElements((e) {
      final w = e.widget;
      if (w is Offstage && w.offstage) hidden = true;
      if (w is Visibility && !w.visible) hidden = true;
      if (w is TickerMode && !w.enabled) hidden = true;
      return !hidden;
    });
    if (hidden) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Where every marked thing is on screen now: for the store pictures' arrows (test/shots/).
  @visibleForTesting
  static Map<String, Rect> allRects() => {
        for (final id in _keys.keys)
          if (rectOf(id) case final r?) id: r,
      };

  static Rect? rectOf(String id) {
    final c = contextOf(id);
    return c == null ? null : rectOfContext(c);
  }

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourTarget._keys.putIfAbsent(widget.id, () => []).add(_key);
  }

  @override
  void dispose() {
    TourTarget._keys[widget.id]?.remove(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

class TourStep {
  const TourStep(this.target, this.text);

  /// The ids of what it lights, alternatives split by |.
  final String target;
  final String Function() text;
}

class Tours {
  Tours._();
  static const welcomeKey = 'tour.welcome';
  static const pagesKey = 'tour.pages';
  static const start = 'home';

  static bool _running = false;
  static bool get running => _running;

  /// Turned off for tests and screenshots, which mark every tour seen instead.
  static bool enabled = true;

  static const labels = {'home': 'Home', 'history': 'History', 'sync': 'Share history', 'look': 'Look'};

  static final Map<String, List<TourStep>> steps = {
    'home': [
      TourStep('home.input', () => onDesktop
          ? 'Paste or type a link here. Ctrl+K finds anything in the app, and a link pasted there is cleaned too.'
          : 'Paste or type a link here, or share one to uwuFix from any app. Highlight a link anywhere and pick Fix link, too.'),
      TourStep('home.clean', () => 'Clean it: trackers go, and links to X, Instagram, TikTok and more turn into ones that show a preview.'),
      TourStep('home.actions', () => 'Copy the clean link, open it, share it, or make a QR code of it.'),
      TourStep('home.history|rail.history', () => 'Every link you clean is kept here, on this device. Share it with your other devices from there.'),
      TourStep('tray.tour|rail.tour', () => 'Show me around has this tour, and the others, again.'),
    ],
    'history': [
      TourStep('history.list|history.empty', () => 'Every link you’ve cleaned, newest first, with its page’s title. Tap one to clean it again.'),
      TourStep('history.delete', () => 'The bin deletes one link from your history.'),
      TourStep('history.share', () => 'Share history with your phone, computer or the website, straight from one to the other.'),
      TourStep('history.clear', () => 'Clear all empties your history on this device.'),
    ],
    'sync': [
      TourStep('sync.tabs', () => 'One device shows a code, and the other enters it.'),
      TourStep('sync.code|sync.join', () => 'On the other device, type this code, scan the QR code or open the link. Or type the code the other device shows.'),
      TourStep('sync.note', () => 'Both have to be on the same wifi, or one on the other’s hotspot. Your history goes straight between them, through no server.'),
    ],
    'look': [
      TourStep('look.style', () => 'Material You takes its colours from your device; UwU Apps is the website’s own look.'),
      TourStep('look.mode', () => 'Light, dark, by the clock, or as your device is.'),
      TourStep('look.colour', () => 'The brand colour, for the UwU Apps look.'),
    ],
  };

  static bool seen(String id) {
    try {
      if (id == start) return Store.I.get(welcomeKey) == 'done';
      return [for (final v in Store.I.list(pagesKey)) '$v'].contains(id);
    } catch (_) {
      return true;
    }
  }

  static void _markSeen(String id) {
    if (id == start) {
      Store.I.put(welcomeKey, 'done');
    } else {
      Store.I.putJson(pagesKey, {...[for (final v in Store.I.list(pagesKey)) '$v'], id}.toList());
    }
  }

  /// For tests and screenshots: a tour left open by a test before doesn't count as running.
  @visibleForTesting
  static void resetForTests() => _running = false;

  /// For tests and screenshots: every tour seen.
  static void markAllSeen() {
    Store.I.put(welcomeKey, 'done');
    Store.I.putJson(pagesKey, steps.keys.where((k) => k != start).toList());
  }

  static Timer? _wait;

  /// The page on show's tour, the first time, once it's drawn (§1: about a second).
  static void forPage() {
    final id = AppNav.page.value;
    if (!enabled || _running || seen(id) || !steps.containsKey(id)) return;
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 1000), () {
      if (AppNav.page.value != id || _running) return;
      // Not over a window someone opened meanwhile.
      if (AppNav.navigatorKey.currentState?.canPop() == true && !onDesktop && id == start) return;
      start_(id);
    });
  }

  /// At start-up: the welcome, unless a link opened something.
  static void init({bool openedByLink = false}) {
    AppNav.page.addListener(forPage);
    if (openedByLink) return;
    forPage();
  }

  static String? _firstShown(String target) {
    for (final id in target.split('|')) {
      if (TourTarget.rectOf(id) != null) return id;
    }
    return null;
  }

  /// [id]'s tour, on its page (switching to it, and back after).
  static Future<void> start_(String id) async {
    final context = AppNav.context;
    final list = steps[id];
    if (context == null || list == null || _running) return;
    _running = true;
    final from = AppNav.page.value;
    if (from != id) {
      AppNav.showPage(id);
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
    final shown = [for (final s in list) if (_firstShown(s.target) != null) s];
    _markSeen(id);
    final ctx = AppNav.context;
    if (shown.isEmpty || ctx == null || !ctx.mounted) {
      _running = false;
      return;
    }
    await Navigator.of(ctx, rootNavigator: true).push(PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (_, _, _) => _TourOverlay(steps: shown),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
    _running = false;
    // Back where it began, which may be a page whose own tour is still to see.
    if (AppNav.page.value != from && from != id) AppNav.showPage(from);
    Timer(const Duration(milliseconds: 600), forPage);
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps});
  final List<TourStep> steps;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with TickerProviderStateMixin {
  int _i = 0;
  Rect? _rect;
  Size? _card; // the card's size as last measured
  double? _cardWidth; // narrowed to fit beside its thing
  bool _measuring = true;
  final _cardKey = GlobalKey();
  final _next = FocusNode();
  late final _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    // Once it's in the tree, where it can read the screen's size.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    _draw.dispose();
    _next.dispose();
    super.dispose();
  }

  String get _targetId {
    for (final id in widget.steps[_i].target.split('|')) {
      if (TourTarget.contextOf(id) != null) return id;
    }
    return widget.steps[_i].target.split('|').first;
  }

  // §3.1: scrolled into view first (inside whatever scrolls it), then lit where it ends up.
  Future<void> _reveal() async {
    final c = TourTarget.contextOf(_targetId);
    if (c != null && c.mounted) {
      final r = TourTarget.rectOfContext(c);
      final h = MediaQuery.sizeOf(context).height;
      final tall = r != null && r.height > h * 0.6;
      final reduce = MediaQuery.of(context).disableAnimations;
      try {
        await Scrollable.ensureVisible(c,
            alignment: tall ? 0.0 : 0.5, duration: reduce ? Duration.zero : const Duration(milliseconds: 250), curve: Curves.easeOut);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _rect = TourTarget.rectOf(_targetId);
      _measuring = true;
      _cardWidth = null;
    });
    _measure();
    if (MediaQuery.of(context).disableAnimations) {
      _draw.value = 1;
    } else {
      _draw.forward(from: 0);
    }
    _next.requestFocus();
  }

  // The card is drawn once out of sight to be measured, then placed.
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      setState(() {
        _card = box.size;
        _measuring = false;
      });
    });
  }

  void _go() {
    if (_i < widget.steps.length - 1) {
      setState(() => _i++);
      _reveal();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final last = _i == widget.steps.length - 1;
    final rect = _rect ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
    final maxCard = math.min(460.0, size.width - 24);
    final layout = _measuring || _card == null ? null : _place(size, rect, _card!);
    // Narrower beside its thing: measured again at that width.
    if (layout != null && layout.width != null && _cardWidth != layout.width) {
      _cardWidth = layout.width;
      _measuring = true;
      _measure();
    }
    final reduce = MediaQuery.of(context).disableAnimations;

    final card = Container(
      key: _cardKey,
      width: _cardWidth ?? maxCard,
      padding: layout?.solid == true ? const EdgeInsets.fromLTRB(16, 14, 16, 14) : EdgeInsets.zero,
      decoration: layout?.solid == true
          ? BoxDecoration(color: const Color(0xEB080E0A), borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 8))])
          : null,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          liveRegion: true,
          child: Text(widget.steps[_i].text(),
              style: const TextStyle(color: _chalk, fontSize: 20.8, height: 1.35, shadows: [Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 1))])),
        ),
        const SizedBox(height: 14),
        Row(children: [
          ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var n = 0; n < widget.steps.length; n++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 6),
                  width: n == _i ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(color: n == _i ? _chalk : _chalk.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(999)),
                ),
            ]),
          ),
          const Spacer(),
          FilledButton(
            focusNode: _next,
            style: FilledButton.styleFrom(backgroundColor: _chalk, foregroundColor: const Color(0xFF1A221D), shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10)),
            onPressed: _go,
            child: Text(last ? 'Done' : 'Next'),
          ),
        ]),
      ]),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.arrowRight): _go,
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: widget.steps[_i].text(),
          child: Material(
            type: MaterialType.transparency,
            child: Stack(children: [
              // The dim, with its hole gliding from one thing to the next.
              Positioned.fill(
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: rect.inflate(8)),
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  builder: (_, r, _) => CustomPaint(painter: _Spot(r ?? rect.inflate(8))),
                ),
              ),
              if (layout != null && layout.arrow != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(animation: _draw, builder: (_, _) => CustomPaint(painter: _Arrow(layout.arrow!, _draw.value))),
                  ),
                ),
              Positioned(
                left: layout?.left ?? 0,
                top: layout?.top ?? 0,
                child: Opacity(opacity: layout == null ? 0 : 1, child: card),
              ),
              Positioned(
                left: math.max(16, pad.left + 12),
                top: math.max(16, pad.top + 12),
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: _chalk, textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16.8)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static const _m = 12.0, _edge = 20.0, _gapMin = 36.0, _gapMax = 70.0, _cardMin = 220.0, _pad = 8.0;

  // §3: the card on the side with room, lined up with its thing, and the arrow between them, all
  // of it on screen.
  _Layout _place(Size s, Rect r, Size card) {
    double clamp(double lo, double v, double hi) => math.max(lo, math.min(v, math.max(lo, hi)));
    final vw = s.width, vh = s.height;
    final v = Rect.fromLTRB(clamp(0, r.left, vw), clamp(0, r.top, vh), clamp(0, r.right, vw), clamp(0, r.bottom, vh));
    var cw = card.width, ch = card.height;
    final room = {
      'below': vh - v.bottom - _pad - _m,
      'above': v.top - _pad - _m,
      'right': vw - v.right - _pad - _m,
      'left': v.left - _pad - _m,
    };
    String? side;
    double? width;
    if (math.max(room['below']!, room['above']!) >= ch + _gapMin) {
      side = room['below']! >= room['above']! ? 'below' : 'above';
    } else {
      final sd = room['right']! >= room['left']! ? 'right' : 'left';
      final fit = room[sd]! - _gapMin;
      if (fit >= math.min(cw, _cardMin)) {
        if (fit < cw) {
          // Narrower text runs taller: about in proportion, checked on the next measure.
          width = fit;
          ch = ch * cw / fit;
          cw = fit;
        }
        if (ch <= vh - _m * 2) {
          side = sd;
        } else {
          width = null;
        }
      }
    }
    if (side == null) {
      final left = clamp(_m, (vw - cw) / 2, vw - cw - _m);
      final top = clamp(_m, v.center.dy > vh / 2 ? _m : vh - ch - _m - 28, vh - ch - _m);
      return _Layout(left, top, null, true, null);
    }
    final midX = v.center.dx, midY = v.center.dy;
    double left, top, sx, sy, tx, ty;
    if (side == 'below' || side == 'above') {
      final gap = clamp(_gapMin, room[side]! - ch, _gapMax);
      left = clamp(_m, midX - cw / 2, vw - cw - _m);
      top = side == 'below' ? v.bottom + _pad + gap : v.top - _pad - gap - ch;
      top = clamp(_m, top, vh - ch - _m);
      tx = clamp(v.left + 12, midX, v.right - 12);
      ty = side == 'below' ? v.bottom + _pad + 4 : v.top - _pad - 4;
      sx = clamp(left + 24, tx, left + cw - 24);
      sy = side == 'below' ? top - 6 : top + ch + 6;
    } else {
      final gap = clamp(_gapMin, room[side]! - cw, _gapMax);
      left = side == 'right' ? v.right + _pad + gap : v.left - _pad - gap - cw;
      left = clamp(_m, left, vw - cw - _m);
      top = clamp(_m, midY - ch / 2, vh - ch - _m);
      tx = side == 'right' ? v.right + _pad + 4 : v.left - _pad - 4;
      ty = clamp(v.top + 12, midY, v.bottom - 12);
      sx = side == 'right' ? left - 6 : left + cw + 6;
      sy = clamp(top + 16, ty, top + ch - 16);
    }
    // Every point of the arrow EDGE in from the screen's edge, so none of it is cut off.
    double inX(double x) => clamp(_edge, x, vw - _edge);
    double inY(double y) => clamp(_edge, y, vh - _edge);
    tx = inX(tx);
    ty = inY(ty);
    sx = inX(sx);
    sy = inY(sy);
    final dx = tx - sx, dy = ty - sy;
    final control = Offset(inX((sx + tx) / 2 - dy * 0.2), inY((sy + ty) / 2 + dx * 0.2));
    return _Layout(left, top, width, false, (Offset(sx, sy), control, Offset(tx, ty)));
  }
}

const _chalk = Color(0xFFF6F1E6);

class _Layout {
  const _Layout(this.left, this.top, this.width, this.solid, this.arrow);
  final double left, top;
  final double? width;
  final bool solid;
  final (Offset, Offset, Offset)? arrow;
}

class _Spot extends CustomPainter {
  _Spot(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(hole, const Radius.circular(18));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(r),
      Paint()..color = const Color(0xDB080E0A),
    );
    // A soft white glow just around it.
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0x59FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12),
    );
  }

  @override
  bool shouldRepaint(_Spot old) => old.hole != hole;
}

/// The chalk arrow: a bowed line drawing itself in, then its head, a little rough, as chalk is.
class _Arrow extends CustomPainter {
  _Arrow(this.points, this.t);
  final (Offset, Offset, Offset) points;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final (s, c, e) = points;
    final paint = Paint()
      ..color = _chalk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The curve, as small steps nudged a fraction of a pixel by a fixed noise: chalk, not ink.
    final line = Path();
    const n = 48;
    for (var i = 0; i <= n; i++) {
      final u = i / n;
      final p = Offset(
        (1 - u) * (1 - u) * s.dx + 2 * (1 - u) * u * c.dx + u * u * e.dx,
        (1 - u) * (1 - u) * s.dy + 2 * (1 - u) * u * c.dy + u * u * e.dy,
      );
      final j = Offset(math.sin(i * 12.9898) * 0.7, math.cos(i * 78.233) * 0.7);
      if (i == 0) {
        line.moveTo(p.dx, p.dy);
      } else {
        line.lineTo(p.dx + j.dx, p.dy + j.dy);
      }
    }
    for (final m in line.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * t.clamp(0.0, 1.0)), paint);
    }
    if (t < 1) return;
    final ang = math.atan2(e.dy - c.dy, e.dx - c.dx);
    const len = 14.0;
    final a1 = ang + math.pi * 0.8, a2 = ang - math.pi * 0.8;
    canvas.drawPath(
      Path()
        ..moveTo(e.dx + math.cos(a1) * len, e.dy + math.sin(a1) * len)
        ..lineTo(e.dx, e.dy)
        ..lineTo(e.dx + math.cos(a2) * len, e.dy + math.sin(a2) * len),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Arrow old) => old.points != points || old.t != t;
}

/// Show me around: each page's tour again.
Future<void> showTourPicker(BuildContext context) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Show me around'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in Tours.labels.entries)
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Timer(const Duration(milliseconds: 300), () => Tours.start_(e.key));
                },
                child: Text(e.value),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Each page shows you around the first time you open it. Pick one to see its tour again.',
              style: TextStyle(color: context.fx.muted, fontSize: 13.6)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );

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

  /// The newest marked thing with [id] that's on screen, if there is one.
  static BuildContext? contextOf(String id) {
    final keys = _keys[id];
    if (keys == null) {
      return null;
    }
    for (final key in keys.reversed) {
      final targetContext = key.currentContext;
      if (targetContext != null && rectOfContext(targetContext) != null) {
        return targetContext;
      }
    }
    return null;
  }

  /// Where [context]'s widget is on screen, or null if it isn't drawn or is hidden.
  static Rect? rectOfContext(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    // Not offstage (a page of the desktop's stack that isn't on show, say).
    var hidden = false;
    context.visitAncestorElements((element) {
      final ancestor = element.widget;
      if (ancestor is Offstage && ancestor.offstage) {
        hidden = true;
      }
      if (ancestor is Visibility && !ancestor.visible) {
        hidden = true;
      }
      if (ancestor is TickerMode && !ancestor.enabled) {
        hidden = true;
      }
      return !hidden;
    });
    if (hidden) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Where every marked thing is on screen now: for the store pictures' arrows (test/shots/).
  @visibleForTesting
  static Map<String, Rect> allRects() {
    final rects = <String, Rect>{};
    for (final id in _keys.keys) {
      final rect = rectOf(id);
      if (rect != null) {
        rects[id] = rect;
      }
    }
    return rects;
  }

  static Rect? rectOf(String id) {
    final targetContext = contextOf(id);
    if (targetContext == null) {
      return null;
    }
    return rectOfContext(targetContext);
  }

  @override
  State<TourTarget> createState() {
    return _TourTargetState();
  }
}

class _TourTargetState extends State<TourTarget> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    TourTarget._keys
        .putIfAbsent(widget.id, () {
          return [];
        })
        .add(_key);
  }

  @override
  void dispose() {
    TourTarget._keys[widget.id]?.remove(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

/// One step of a tour: what it lights, and the line saying what it does.
class TourStep {
  const TourStep(this.target, this.text);

  /// The ids of what it lights, alternatives split by |.
  final String target;
  final String Function() text;
}

/// Every page's tour, which have been seen, and starting one.
class Tours {
  Tours._();
  static const welcomeKey = 'tour.welcome';
  static const pagesKey = 'tour.pages';
  static const welcomePage = 'home';

  static bool _running = false;
  static bool get running {
    return _running;
  }

  /// Turned off for tests and screenshots, which mark every tour seen instead.
  static bool enabled = true;

  static const labels = {
    'home': 'Home',
    'history': 'History',
    'sync': 'Share history',
    'look': 'Look',
  };

  static final Map<String, List<TourStep>> steps = {
    'home': [
      TourStep('home.input', () {
        if (onDesktop) {
          return 'Paste or type a link here. Ctrl+K finds anything in the app, and a link pasted there is cleaned too.';
        }
        return 'Paste or type a link here, or share one to uwuFix from any app. Highlight a link anywhere and pick Fix link, too.';
      }),
      TourStep('home.clean', () {
        return 'Clean it: trackers go, and links to X, Instagram, TikTok and more turn into ones that show a preview.';
      }),
      TourStep('home.actions', () {
        return 'Copy the clean link, open it, share it, or make a QR code of it.';
      }),
      TourStep('home.history|rail.history', () {
        return 'Every link you clean is kept here, on this device. Share it with your other devices from there.';
      }),
      TourStep('tray.tour|rail.tour', () {
        return 'Show me around has this tour, and the others, again.';
      }),
    ],
    'history': [
      TourStep('history.list|history.empty', () {
        return 'Every link you’ve cleaned, newest first, with its page’s title. Tap one to clean it again.';
      }),
      TourStep('history.delete', () {
        return 'The bin deletes one link from your history.';
      }),
      TourStep('history.share', () {
        return 'Share history with your phone, computer or the website, straight from one to the other.';
      }),
      TourStep('history.clear', () {
        return 'Clear all empties your history on this device.';
      }),
    ],
    'sync': [
      TourStep('sync.tabs', () {
        return 'One device shows a code, and the other enters it.';
      }),
      TourStep('sync.code|sync.join', () {
        return 'On the other device, type this code, scan the QR code or open the link. Or type the code the other device shows.';
      }),
      TourStep('sync.note', () {
        return 'Both have to be on the same wifi, or one on the other’s hotspot. Your history goes straight between them, through no server.';
      }),
    ],
    'look': [
      TourStep('look.style', () {
        return '${AppLook.I.deviceLookName} takes its colours from your device; UwU Apps is the website’s own look.';
      }),
      TourStep('look.mode', () {
        return 'Light, dark, by the clock, or as your device is.';
      }),
      TourStep('look.colour', () {
        return 'The brand colour, for the UwU Apps look.';
      }),
    ],
  };

  /// The ids of the pages (other than home) whose tours have been seen.
  static List<String> _seenPages() {
    final pages = <String>[];
    for (final value in Store.I.list(pagesKey)) {
      pages.add('$value');
    }
    return pages;
  }

  static bool seen(String id) {
    try {
      if (id == welcomePage) {
        return Store.I.get(welcomeKey) == 'done';
      }
      return _seenPages().contains(id);
    } catch (_) {
      return true;
    }
  }

  static void _markSeen(String id) {
    if (id == welcomePage) {
      Store.I.put(welcomeKey, 'done');
    } else {
      final pages = <String>{};
      pages.addAll(_seenPages());
      pages.add(id);
      Store.I.putJson(pagesKey, pages.toList());
    }
  }

  /// For tests and screenshots: a tour left open by a test before doesn't count as running.
  @visibleForTesting
  static void resetForTests() {
    _running = false;
  }

  /// For tests and screenshots: every tour seen.
  static void markAllSeen() {
    Store.I.put(welcomeKey, 'done');
    final pages = <String>[];
    for (final page in steps.keys) {
      if (page != welcomePage) {
        pages.add(page);
      }
    }
    Store.I.putJson(pagesKey, pages);
  }

  static Timer? _waitTimer;

  /// The page on show's tour, the first time, once it's drawn (§1: about a second).
  static void forPage() {
    final id = AppNav.page.value;
    if (!enabled || _running || seen(id) || !steps.containsKey(id)) {
      return;
    }
    _waitTimer?.cancel();
    _waitTimer = Timer(const Duration(milliseconds: 1000), () {
      if (AppNav.page.value != id || _running) {
        return;
      }
      // Not over a window someone opened meanwhile.
      if (AppNav.navigatorKey.currentState?.canPop() == true &&
          !onDesktop &&
          id == welcomePage) {
        return;
      }
      start_(id);
    });
  }

  /// At start-up: the welcome, unless a link opened something.
  static void init({bool openedByLink = false}) {
    AppNav.page.addListener(forPage);
    if (openedByLink) {
      return;
    }
    forPage();
  }

  /// The first of [target]'s alternative ids that's on screen.
  static String? _firstShown(String target) {
    for (final id in target.split('|')) {
      if (TourTarget.rectOf(id) != null) {
        return id;
      }
    }
    return null;
  }

  /// [id]'s tour, on its page (switching to it, and back after).
  static Future<void> start_(String id) async {
    final context = AppNav.context;
    final list = steps[id];
    if (context == null || list == null || _running) {
      return;
    }
    _running = true;
    final startPage = AppNav.page.value;
    if (startPage != id) {
      AppNav.showPage(id);
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
    final shown = <TourStep>[];
    for (final step in list) {
      if (_firstShown(step.target) != null) {
        shown.add(step);
      }
    }
    _markSeen(id);
    final currentContext = AppNav.context;
    if (shown.isEmpty || currentContext == null || !currentContext.mounted) {
      _running = false;
      return;
    }
    await Navigator.of(currentContext, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        pageBuilder: (_, _, _) {
          return _TourOverlay(steps: shown);
        },
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    _running = false;
    // Back where it began, which may be a page whose own tour is still to see.
    if (AppNav.page.value != startPage && startPage != id) {
      AppNav.showPage(startPage);
    }
    Timer(const Duration(milliseconds: 600), forPage);
  }
}

/// The tour itself, over the page: the dim with its lit hole, the card, and the arrow.
class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps});
  final List<TourStep> steps;

  @override
  State<_TourOverlay> createState() {
    return _TourOverlayState();
  }
}

class _TourOverlayState extends State<_TourOverlay>
    with TickerProviderStateMixin {
  int _stepIndex = 0;
  Rect? _rect;
  Size? _cardSize; // the card's size as last measured
  double? _cardWidth; // narrowed to fit beside its thing
  bool _measuring = true;
  final _cardKey = GlobalKey();
  final _nextFocus = FocusNode();
  late final _drawController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    // Once it's in the tree, where it can read the screen's size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reveal();
    });
  }

  @override
  void dispose() {
    _drawController.dispose();
    _nextFocus.dispose();
    super.dispose();
  }

  /// The id of what this step lights: the first alternative on screen, or else the first.
  String get _targetId {
    for (final id in widget.steps[_stepIndex].target.split('|')) {
      if (TourTarget.contextOf(id) != null) {
        return id;
      }
    }
    return widget.steps[_stepIndex].target.split('|').first;
  }

  // §3.1: scrolled into view first (inside whatever scrolls it), then lit where it ends up.
  Future<void> _reveal() async {
    final targetContext = TourTarget.contextOf(_targetId);
    if (targetContext != null && targetContext.mounted) {
      final targetRect = TourTarget.rectOfContext(targetContext);
      final screenHeight = MediaQuery.sizeOf(context).height;
      final tall = targetRect != null && targetRect.height > screenHeight * 0.6;
      final reduceMotion = MediaQuery.of(context).disableAnimations;
      double alignment;
      if (tall) {
        alignment = 0.0;
      } else {
        alignment = 0.5;
      }
      Duration duration;
      if (reduceMotion) {
        duration = Duration.zero;
      } else {
        duration = const Duration(milliseconds: 250);
      }
      try {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: alignment,
          duration: duration,
          curve: Curves.easeOut,
        );
      } catch (_) {}
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _rect = TourTarget.rectOf(_targetId);
      _measuring = true;
      _cardWidth = null;
    });
    _measure();
    if (MediaQuery.of(context).disableAnimations) {
      _drawController.value = 1;
    } else {
      _drawController.forward(from: 0);
    }
    _nextFocus.requestFocus();
  }

  // The card is drawn once out of sight to be measured, then placed.
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        return;
      }
      setState(() {
        _cardSize = box.size;
        _measuring = false;
      });
    });
  }

  /// Next: the next step, or the end of the tour after the last.
  void _goNext() {
    if (_stepIndex < widget.steps.length - 1) {
      setState(() {
        _stepIndex++;
      });
      _reveal();
    } else {
      Navigator.pop(context);
    }
  }

  void _close() {
    Navigator.pop(context);
  }

  /// The row of dots, one per step, the current one long.
  Widget _buildDots() {
    final dots = <Widget>[];
    for (var dotIndex = 0; dotIndex < widget.steps.length; dotIndex++) {
      final current = dotIndex == _stepIndex;
      double width;
      Color color;
      if (current) {
        width = 20;
        color = _chalk;
      } else {
        width = 7;
        color = _chalk.withValues(alpha: 0.4);
      }
      dots.add(
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(right: 6),
          width: width,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final last = _stepIndex == widget.steps.length - 1;
    Rect rect;
    final litRect = _rect;
    if (litRect != null) {
      rect = litRect;
    } else {
      rect = Rect.fromCenter(
        center: size.center(Offset.zero),
        width: 0,
        height: 0,
      );
    }
    final maxCardWidth = math.min(460.0, size.width - 24);
    _Layout? layout;
    final cardSize = _cardSize;
    if (!_measuring && cardSize != null) {
      layout = _place(size, rect, cardSize);
    }
    // Narrower beside its thing: measured again at that width.
    if (layout != null && layout.width != null && _cardWidth != layout.width) {
      _cardWidth = layout.width;
      _measuring = true;
      _measure();
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // A card with no room clear of its thing takes a dark backing of its own.
    final solid = layout?.solid == true;
    EdgeInsets cardPadding;
    BoxDecoration? cardDecoration;
    if (solid) {
      cardPadding = const EdgeInsets.fromLTRB(16, 14, 16, 14);
      cardDecoration = BoxDecoration(
        color: const Color(0xEB080E0A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 30,
            offset: Offset(0, 8),
          ),
        ],
      );
    } else {
      cardPadding = EdgeInsets.zero;
      cardDecoration = null;
    }
    double cardWidth = maxCardWidth;
    final narrowedWidth = _cardWidth;
    if (narrowedWidth != null) {
      cardWidth = narrowedWidth;
    }
    String nextLabel;
    if (last) {
      nextLabel = 'Done';
    } else {
      nextLabel = 'Next';
    }
    Duration holeDuration;
    if (reduceMotion) {
      holeDuration = Duration.zero;
    } else {
      holeDuration = const Duration(milliseconds: 300);
    }
    double cardLeft = 0;
    double cardTop = 0;
    double cardOpacity = 0;
    if (layout != null) {
      cardLeft = layout.left;
      cardTop = layout.top;
      cardOpacity = 1;
    }
    final arrow = layout?.arrow;

    final card = Container(
      key: _cardKey,
      width: cardWidth,
      padding: cardPadding,
      decoration: cardDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              widget.steps[_stepIndex].text(),
              style: const TextStyle(
                color: _chalk,
                fontSize: 20.8,
                height: 1.35,
                shadows: [
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 8,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ExcludeSemantics(child: _buildDots()),
              const Spacer(),
              FilledButton(
                focusNode: _nextFocus,
                style: FilledButton.styleFrom(
                  backgroundColor: _chalk,
                  foregroundColor: const Color(0xFF1A221D),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 10,
                  ),
                ),
                onPressed: _goNext,
                child: Text(nextLabel),
              ),
            ],
          ),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _goNext,
      },
      child: Focus(
        autofocus: true,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: widget.steps[_stepIndex].text(),
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                // The dim, with its hole gliding from one thing to the next.
                Positioned.fill(
                  child: TweenAnimationBuilder<Rect?>(
                    tween: RectTween(end: rect.inflate(8)),
                    duration: holeDuration,
                    curve: Curves.easeOut,
                    builder: (_, animatedRect, _) {
                      Rect hole = rect.inflate(8);
                      if (animatedRect != null) {
                        hole = animatedRect;
                      }
                      return CustomPaint(painter: _Spot(hole));
                    },
                  ),
                ),
                if (arrow != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _drawController,
                        builder: (_, _) {
                          return CustomPaint(
                            painter: _Arrow(arrow, _drawController.value),
                          );
                        },
                      ),
                    ),
                  ),
                Positioned(
                  left: cardLeft,
                  top: cardTop,
                  child: Opacity(opacity: cardOpacity, child: card),
                ),
                Positioned(
                  left: math.max(16, safePadding.left + 12),
                  top: math.max(16, safePadding.top + 12),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: _chalk,
                      textStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontSize: 16.8),
                    ),
                    onPressed: _close,
                    child: const Text('Skip'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _margin = 12.0,
      _edgeInset = 20.0,
      _minimumGap = 36.0,
      _maximumGap = 70.0,
      _minimumCardWidth = 220.0,
      _targetPadding = 8.0;

  /// [value] kept between [low] and [high] (and never under [low], even if [high] is).
  static double _clamp(double low, double value, double high) {
    return math.max(low, math.min(value, math.max(low, high)));
  }

  // §3: the card on the side with room, lined up with its thing, and the arrow between them, all
  // of it on screen.
  _Layout _place(Size screen, Rect target, Size card) {
    final screenWidth = screen.width, screenHeight = screen.height;
    // The part of the thing that's on screen.
    final visible = Rect.fromLTRB(
      _clamp(0, target.left, screenWidth),
      _clamp(0, target.top, screenHeight),
      _clamp(0, target.right, screenWidth),
      _clamp(0, target.bottom, screenHeight),
    );
    var cardWidth = card.width, cardHeight = card.height;
    final room = {
      'below': screenHeight - visible.bottom - _targetPadding - _margin,
      'above': visible.top - _targetPadding - _margin,
      'right': screenWidth - visible.right - _targetPadding - _margin,
      'left': visible.left - _targetPadding - _margin,
    };
    String? side;
    double? width;
    if (math.max(room['below']!, room['above']!) >= cardHeight + _minimumGap) {
      if (room['below']! >= room['above']!) {
        side = 'below';
      } else {
        side = 'above';
      }
    } else {
      String sideways;
      if (room['right']! >= room['left']!) {
        sideways = 'right';
      } else {
        sideways = 'left';
      }
      final available = room[sideways]! - _minimumGap;
      if (available >= math.min(cardWidth, _minimumCardWidth)) {
        if (available < cardWidth) {
          // Narrower text runs taller: about in proportion, checked on the next measure.
          width = available;
          cardHeight = cardHeight * cardWidth / available;
          cardWidth = available;
        }
        if (cardHeight <= screenHeight - _margin * 2) {
          side = sideways;
        } else {
          width = null;
        }
      }
    }
    if (side == null) {
      // No room clear of it: centred across, at the top or the bottom away from it, on a backing.
      final left = _clamp(
        _margin,
        (screenWidth - cardWidth) / 2,
        screenWidth - cardWidth - _margin,
      );
      double preferredTop;
      if (visible.center.dy > screenHeight / 2) {
        preferredTop = _margin;
      } else {
        preferredTop = screenHeight - cardHeight - _margin - 28;
      }
      final top = _clamp(
        _margin,
        preferredTop,
        screenHeight - cardHeight - _margin,
      );
      return _Layout(left, top, null, true, null);
    }
    final middleX = visible.center.dx, middleY = visible.center.dy;
    // The card's corner, the arrow's start (by the card) and its tip (by the thing).
    double left, top, startX, startY, tipX, tipY;
    if (side == 'below' || side == 'above') {
      final gap = _clamp(_minimumGap, room[side]! - cardHeight, _maximumGap);
      left = _clamp(
        _margin,
        middleX - cardWidth / 2,
        screenWidth - cardWidth - _margin,
      );
      if (side == 'below') {
        top = visible.bottom + _targetPadding + gap;
      } else {
        top = visible.top - _targetPadding - gap - cardHeight;
      }
      top = _clamp(_margin, top, screenHeight - cardHeight - _margin);
      tipX = _clamp(visible.left + 12, middleX, visible.right - 12);
      if (side == 'below') {
        tipY = visible.bottom + _targetPadding + 4;
      } else {
        tipY = visible.top - _targetPadding - 4;
      }
      startX = _clamp(left + 24, tipX, left + cardWidth - 24);
      if (side == 'below') {
        startY = top - 6;
      } else {
        startY = top + cardHeight + 6;
      }
    } else {
      final gap = _clamp(_minimumGap, room[side]! - cardWidth, _maximumGap);
      if (side == 'right') {
        left = visible.right + _targetPadding + gap;
      } else {
        left = visible.left - _targetPadding - gap - cardWidth;
      }
      left = _clamp(_margin, left, screenWidth - cardWidth - _margin);
      top = _clamp(
        _margin,
        middleY - cardHeight / 2,
        screenHeight - cardHeight - _margin,
      );
      if (side == 'right') {
        tipX = visible.right + _targetPadding + 4;
      } else {
        tipX = visible.left - _targetPadding - 4;
      }
      tipY = _clamp(visible.top + 12, middleY, visible.bottom - 12);
      if (side == 'right') {
        startX = left - 6;
      } else {
        startX = left + cardWidth + 6;
      }
      startY = _clamp(top + 16, tipY, top + cardHeight - 16);
    }
    // Every point of the arrow EDGE in from the screen's edge, so none of it is cut off.
    double insideX(double pointX) {
      return _clamp(_edgeInset, pointX, screenWidth - _edgeInset);
    }

    double insideY(double pointY) {
      return _clamp(_edgeInset, pointY, screenHeight - _edgeInset);
    }

    tipX = insideX(tipX);
    tipY = insideY(tipY);
    startX = insideX(startX);
    startY = insideY(startY);
    final deltaX = tipX - startX, deltaY = tipY - startY;
    final control = Offset(
      insideX((startX + tipX) / 2 - deltaY * 0.2),
      insideY((startY + tipY) / 2 + deltaX * 0.2),
    );
    return _Layout(left, top, width, false, (
      Offset(startX, startY),
      control,
      Offset(tipX, tipY),
    ));
  }
}

const _chalk = Color(0xFFF6F1E6);

/// Where a step's card goes, its narrowed width if any, whether it needs a backing of its own,
/// and the arrow's start, bend and tip.
class _Layout {
  const _Layout(this.left, this.top, this.width, this.solid, this.arrow);
  final double left, top;
  final double? width;
  final bool solid;
  final (Offset, Offset, Offset)? arrow;
}

/// The dim over the page, with a rounded hole where its thing is lit.
class _Spot extends CustomPainter {
  _Spot(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final roundedHole = RRect.fromRectAndRadius(
      hole,
      const Radius.circular(18),
    );
    final dim = Path();
    dim.fillType = PathFillType.evenOdd;
    dim.addRect(Offset.zero & size);
    dim.addRRect(roundedHole);
    canvas.drawPath(dim, Paint()..color = const Color(0xDB080E0A));
    // A soft white glow just around it.
    canvas.drawRRect(
      roundedHole,
      Paint()
        ..color = const Color(0x59FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12),
    );
  }

  @override
  bool shouldRepaint(_Spot oldDelegate) {
    return oldDelegate.hole != hole;
  }
}

/// The chalk arrow: a bowed line drawing itself in, then its head, a little rough, as chalk is.
class _Arrow extends CustomPainter {
  _Arrow(this.points, this.progress);
  final (Offset, Offset, Offset) points;

  /// How much of it is drawn, from 0 to 1.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final (start, control, end) = points;
    final paint = Paint()
      ..color = _chalk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // The curve, as small steps nudged a fraction of a pixel by a fixed noise: chalk, not ink.
    final line = Path();
    const stepCount = 48;
    for (var stepIndex = 0; stepIndex <= stepCount; stepIndex++) {
      final fraction = stepIndex / stepCount;
      final point = Offset(
        (1 - fraction) * (1 - fraction) * start.dx +
            2 * (1 - fraction) * fraction * control.dx +
            fraction * fraction * end.dx,
        (1 - fraction) * (1 - fraction) * start.dy +
            2 * (1 - fraction) * fraction * control.dy +
            fraction * fraction * end.dy,
      );
      final jitter = Offset(
        math.sin(stepIndex * 12.9898) * 0.7,
        math.cos(stepIndex * 78.233) * 0.7,
      );
      if (stepIndex == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx + jitter.dx, point.dy + jitter.dy);
      }
    }
    for (final metric in line.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        paint,
      );
    }
    if (progress < 1) {
      return;
    }
    final angle = math.atan2(end.dy - control.dy, end.dx - control.dx);
    const headLength = 14.0;
    final leftAngle = angle + math.pi * 0.8, rightAngle = angle - math.pi * 0.8;
    final head = Path();
    head.moveTo(
      end.dx + math.cos(leftAngle) * headLength,
      end.dy + math.sin(leftAngle) * headLength,
    );
    head.lineTo(end.dx, end.dy);
    head.lineTo(
      end.dx + math.cos(rightAngle) * headLength,
      end.dy + math.sin(rightAngle) * headLength,
    );
    canvas.drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_Arrow oldDelegate) {
    return oldDelegate.points != points || oldDelegate.progress != progress;
  }
}

/// Show me around: each page's tour again.
Future<void> showTourPicker(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Show me around'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in Tours.labels.entries)
                  OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      Timer(const Duration(milliseconds: 300), () {
                        Tours.start_(entry.key);
                      });
                    },
                    child: Text(entry.value),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Each page shows you around the first time you open it. Pick one to see its tour again.',
              style: TextStyle(color: context.fx.muted, fontSize: 13.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

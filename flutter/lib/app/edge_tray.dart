// The Edge Tray (docs/edge-tray-spec.md, the site's js/tray.js): the column of links and actions
// pinned top right, tucked off the edge by its arrow tab and remembered (uwufix.trayOpen, as the
// site keeps it). The phone's; the desktop has its navigation rail instead.
//
// As the spec draws it: the tab, a pill, to the left of the column of rounded-square buttons.
// Collapsing slides the whole tray right until only the tab is left, flush with the edge and flat
// on that side, its chevron turned round; the buttons fade, shrink and slide out together, and
// on opening unroll top to bottom, 18 ms apart. 44 px buttons 16 px from the edge, 40 and 10 on a
// phone up to 480 px wide.
//
//   Telegram bot, Discord bot, Buy Augy a coffee
//   ---
//   Notifications (Android, when built with Firebase), Check for app updates (GitHub's APK),
//   Report a bug, Show me around, Look
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../features/bug/bug_report.dart';
import '../features/look/look_page.dart';
import '../features/notify/notify_sheet.dart';
import '../features/tour/tour.dart';
import '../features/update/update_bar.dart';
import '../native/native_bridge.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import 'actions.dart';
import 'nav.dart';

const telegramSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>';
const discordSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor"><path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.522 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z"/></svg>';

const telegramUrl = 'https://t.me/uwuFix_bot';
const discordUrl = 'https://discord.com/oauth2/authorize?client_id=1524465330091724880';
const coffeeUrl = 'https://donate.stripe.com/28o2akeAr3hv0DK6oo';

class EdgeTray extends StatefulWidget {
  const EdgeTray({super.key});

  static const storeKey = 'uwufix.trayOpen';

  /// Whether it's out, for the page to make room for it (the site's body.tray-open).
  static final open = ValueNotifier<bool>(true);

  /// The spec's --tray-time and --tray-ease: the tray, its buttons, its tab and the page all move
  /// at this pace.
  static const time = Duration(milliseconds: 340);
  static const ease = Cubic(0.2, 0.8, 0.2, 1);

  static const _tabWidth = 24.0;
  static const _gap = 8.0;

  /// The spec's --glass-btn: 44 px, 40 on a phone up to 480 px wide.
  static double buttonSize(BuildContext context) => MediaQuery.sizeOf(context).width <= 480 ? 40 : 44;

  /// The spec's --edge: 16 px from the right edge (10 on a phone), clear of a landscape notch.
  static double edge(BuildContext context) {
    final inset = MediaQuery.sizeOf(context).width <= 480 ? 10.0 : 16.0;
    return math.max(inset, MediaQuery.paddingOf(context).right + inset);
  }

  /// Up to here the page's 680 px column would meet the tray (style.css's 840 px breakpoint).
  static bool _narrow(BuildContext context) => MediaQuery.sizeOf(context).width <= 840;

  /// The page's whole right padding while the tray's out on a narrow screen: the buttons, their
  /// edge and a 12 px gap (style.css's body.tray-open .app). It stands in for the page's own
  /// padding, not on top of it. None when it's tucked away or the screen is wide.
  static double roomFor(BuildContext context) => open.value && _narrow(context) ? buttonSize(context) + edge(context) + 12 : 0;

  /// How much further in the brand line steps, past the page's right padding, so the tab (level
  /// with it) covers neither the logo nor the name, with a 10 px gap. [pagePad] is the page's
  /// right padding. Out, the tab sits left of the buttons; tucked away, at the edge.
  static double brandStepFor(BuildContext context, double pagePad) {
    if (!_narrow(context)) return 0;
    final tabLeft = open.value ? buttonSize(context) + edge(context) + _gap + _tabWidth : _tabWidth;
    return math.max(0, tabLeft + 10 - pagePad);
  }

  @override
  State<EdgeTray> createState() => _EdgeTrayState();
}

class _EdgeTrayState extends State<EdgeTray> {
  @override
  void initState() {
    super.initState();
    EdgeTray.open.value = Store.I.get(EdgeTray.storeKey) != '0';
  }

  bool get _open => EdgeTray.open.value;

  void _toggle() => setState(() {
    EdgeTray.open.value = !_open;
    Store.I.put(EdgeTray.storeKey, _open ? '1' : '0');
  });

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final open = _open;
    final time = MediaQuery.of(context).disableAnimations ? Duration.zero : EdgeTray.time;
    final size = EdgeTray.buttonSize(context);
    final edge = EdgeTray.edge(context);
    // Far enough that the tab's right side lands on the edge, and 1 px more so its right border
    // goes past it: at the edge it's flat on that side, with no border there.
    final shift = size + EdgeTray._gap + edge + 1;

    Widget button(Widget icon, String label, VoidCallback onPressed) => _Glass(width: size, height: size, label: label, lift: true, onTap: onPressed, child: icon);

    final items = <Widget>[
      button(const SvgIcon(telegramSvg, size: 22), 'Telegram Bot', () => openLink(telegramUrl)),
      button(const SvgIcon(discordSvg, size: 22), 'Invite Discord Bot', () => openLink(discordUrl)),
      button(const Icon(Icons.coffee_outlined), 'Buy me a coffee', () => openLink(coffeeUrl)),
      // Separates the links from the app's own actions.
      Container(width: 24, height: 1, margin: const EdgeInsets.symmetric(vertical: 2), color: fx.ink.withValues(alpha: 0.25)),
      if (Native.has('push')) button(const Icon(Icons.notifications_none), 'Notifications', () => showNotifySheet(context)),
      if (Native.has('checkupdate')) button(const Icon(Icons.download_outlined), 'Check for app updates', () => AppUpdate.openPage()),
      button(const Icon(Icons.bug_report_outlined), 'Report a bug', openBugReport),
      TourTarget(id: 'tray.tour', child: button(const Icon(Icons.help_outline), 'Show me around', () => showTourPicker(context))),
      button(Icon(Theme.of(context).brightness == Brightness.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined), 'Look', () => AppNav.showPage('look')),
    ];

    // Tucked away, the buttons are inert: no focus, no taps, nothing for a screen reader.
    final column = Padding(
      padding: EdgeInsets.only(right: edge),
      child: ExcludeFocus(
        excluding: !open,
        child: IgnorePointer(
          ignoring: !open,
          child: ExcludeSemantics(
            excluding: !open,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: EdgeTray._gap),
                  _Unroll(
                    open: open,
                    delay: Duration(milliseconds: 18 * i),
                    time: time,
                    child: items[i],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // k runs 0 (out) to 1 (tucked away): the slide, the tab's flat side and its chevron.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: open ? 0 : 1),
      duration: time,
      curve: EdgeTray.ease,
      child: column,
      builder: (context, k, column) => Transform.translate(
        offset: Offset(shift * k, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glass(
              width: EdgeTray._tabWidth,
              height: size,
              radius: BorderRadius.horizontal(left: const Radius.circular(12), right: Radius.circular(12 * (1 - k))),
              label: open ? 'Hide menu' : 'Show menu',
              expanded: open,
              onTap: _toggle,
              child: Transform.rotate(angle: math.pi * k, child: const Icon(Icons.chevron_right, size: 16)),
            ),
            const SizedBox(width: EdgeTray._gap),
            column!,
          ],
        ),
      ),
    );
  }
}

/// One of the tray's glass pieces: a button, or the tab. The spec's .glass-btn: a rounded square
/// on the surface colour with its border and shadow, lifting 1 px on hover ([lift]), with a
/// visible outline on keyboard focus.
class _Glass extends StatefulWidget {
  const _Glass({
    required this.width,
    required this.height,
    required this.label,
    required this.onTap,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(14)),
    this.lift = false,
    this.expanded,
  });

  final double width, height;
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius radius;
  final bool lift;
  final bool? expanded;

  @override
  State<_Glass> createState() => _GlassState();
}

class _GlassState extends State<_Glass> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hover = _hover && widget.lift;
    // UwU Apps has the site's glass; Material You its own flat containers.
    final color = fx.uwu ? (hover ? fx.surfaceStrong : fx.surface) : (hover ? scheme.surfaceContainerHighest : scheme.surfaceContainerHigh);
    final keyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        label: widget.label,
        expanded: widget.expanded,
        excludeSemantics: true,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(0, hover ? -1 : 0, 0),
            width: widget.width,
            height: widget.height,
            foregroundDecoration: _focus && keyboard
                ? BoxDecoration(
                    borderRadius: widget.radius,
                    border: Border.all(color: fx.ink, width: 2, strokeAlign: 4),
                  )
                : null,
            decoration: BoxDecoration(
              color: color,
              borderRadius: widget.radius,
              border: fx.uwu ? Border.all(color: fx.border) : null,
              boxShadow: fx.uwu
                  ? [dark ? const BoxShadow(color: Color(0x80000000), blurRadius: 34, offset: Offset(0, 10)) : const BoxShadow(color: Color(0x1A14281E), blurRadius: 30, offset: Offset(0, 10))]
                  : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: widget.radius,
                onTap: widget.onTap,
                onFocusChange: (f) => setState(() => _focus = f),
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(color: fx.ink, size: 22),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tray item's part in the tray opening and closing. Opening, it fades in, slides 12 px back
/// from the edge and grows from 85 % scale, [delay] after the tray starts (18 ms after the one
/// above); closing, it goes at once, with the others. The fade takes 80 % of the time.
class _Unroll extends StatefulWidget {
  const _Unroll({required this.open, required this.delay, required this.time, required this.child});
  final bool open;
  final Duration delay, time;
  final Widget child;

  @override
  State<_Unroll> createState() => _UnrollState();
}

class _UnrollState extends State<_Unroll> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.time, value: widget.open ? 1 : 0);
  Timer? _wait;

  @override
  void didUpdateWidget(_Unroll old) {
    super.didUpdateWidget(old);
    _c.duration = widget.time;
    if (widget.open == old.open) return;
    _wait?.cancel();
    if (!widget.open) {
      _c.reverse();
    } else if (widget.time == Duration.zero) {
      _c.value = 1;
    } else {
      _wait = Timer(widget.delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      // Each way eases out from where it starts, as a CSS transition does.
      final opening = _c.status == AnimationStatus.forward || _c.status == AnimationStatus.completed;
      final move = opening ? EdgeTray.ease.transform(v) : 1 - EdgeTray.ease.transform(1 - v);
      final fade = opening ? Curves.ease.transform(math.min(1, v / 0.8)) : 1 - Curves.ease.transform(math.min(1, (1 - v) / 0.8));
      return Opacity(
        opacity: fade,
        child: Transform.translate(
          offset: Offset(12 * (1 - move), 0),
          child: Transform.scale(scale: 0.85 + 0.15 * move, child: child),
        ),
      );
    },
  );
}

/// The Look page, as the tray opens it on a phone.
Widget lookPage() => const LookPage();

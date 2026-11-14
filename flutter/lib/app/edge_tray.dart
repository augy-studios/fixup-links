// The Edge Tray (docs/edge-tray-spec.md, the site's js/tray.js): the column of links and actions
// pinned top right, tucked off the edge by its arrow tab and remembered (uwufix.trayOpen, as the
// site keeps it). The phone's; the desktop has its navigation rail instead.
//
//   Telegram bot, Discord bot, Buy Augy a coffee
//   ---
//   Notifications (Android, when built with Firebase), Check for app updates (GitHub's APK),
//   Report a bug, Show me around, Look
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
  static const width = 44.0 + 16;

  /// Whether it's out, for the page to make room for it (the site's body.tray-open).
  static final open = ValueNotifier<bool>(true);

  /// The page's right padding: the buttons' width and a gap while it's out on a screen up to
  /// 840 px wide (style.css's body.tray-open .app), none otherwise.
  static double roomFor(double screenWidth) => open.value && screenWidth <= 840 ? 44 + 16 + 12 : 0;

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
    final reduce = MediaQuery.of(context).disableAnimations;
    final buttons = <Widget>[
      RoundButton(icon: const SvgIcon(telegramSvg), label: 'Telegram Bot', onPressed: () => openLink(telegramUrl)),
      RoundButton(icon: const SvgIcon(discordSvg), label: 'Invite Discord Bot', onPressed: () => openLink(discordUrl)),
      RoundButton(icon: const Icon(Icons.coffee_outlined), label: 'Buy me a coffee', onPressed: () => openLink(coffeeUrl)),
      Container(width: 24, height: 2, margin: const EdgeInsets.symmetric(vertical: 2), decoration: BoxDecoration(color: fx.ink.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(2))),
      if (Native.has('push'))
        RoundButton(icon: const Icon(Icons.notifications_none), label: 'Notifications', onPressed: () => showNotifySheet(context)),
      if (Native.has('checkupdate'))
        RoundButton(icon: const Icon(Icons.download_outlined), label: 'Check for app updates', onPressed: () => AppUpdate.openPage()),
      RoundButton(icon: const Icon(Icons.bug_report_outlined), label: 'Report a bug', onPressed: openBugReport),
      TourTarget(
        id: 'tray.tour',
        child: RoundButton(icon: const Icon(Icons.help_outline), label: 'Show me around', onPressed: () => showTourPicker(context)),
      ),
      RoundButton(
        icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
        label: 'Look',
        onPressed: () => AppNav.showPage('look'),
      ),
    ];
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Tooltip(
        message: open ? 'Hide menu' : 'Show menu',
        child: Material(
          color: fx.uwu ? fx.surfaceStrong : Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
          child: InkWell(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
            onTap: _toggle,
            child: Semantics(
              button: true,
              expanded: open,
              label: open ? 'Hide menu' : 'Show menu',
              child: SizedBox(
                width: 28,
                height: 36,
                child: AnimatedRotation(
                  turns: open ? 0 : 0.5,
                  duration: reduce ? Duration.zero : const Duration(milliseconds: 340),
                  child: Icon(Icons.chevron_right, color: fx.ink),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      ClipRect(
        child: AnimatedAlign(
          alignment: Alignment.topLeft,
          widthFactor: open ? 1 : 0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 340),
          curve: const Cubic(0.2, 0.8, 0.2, 1),
          child: ExcludeFocus(
            excluding: !open,
            child: IgnorePointer(
              ignoring: !open,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// The Look page, as the tray opens it on a phone.
Widget lookPage() => const LookPage();

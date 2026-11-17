// The desktop's main window (docs/desktop-features-spec.md §5, flutter-desktop-app-spec.md §2):
//
// - its own title bar, 40 px, in the brand colour: Back and Forward through the pages visited,
//   Reload, the command bar in the middle (Ctrl+K), Copy link, Screenshot and Long screenshot,
//   the update button once one's downloaded, and on Windows and Linux the window's own buttons;
// - a navigation rail on the left (Fix, History, Share history, Look, and Show me around), or a
//   bar at the bottom below 720 px. Its button at the top (or Ctrl+B) collapses it to icons or
//   widens it to names, remembered; until then it's wide over 1300 px;
// - over 1024 px, History beside the cleaner (master and detail): picking a link fills the
//   cleaner in place. It can be put away (its own button, the title bar's, or Ctrl+Shift+H),
//   remembered, leaving the cleaner the whole window;
// - the desktop's keyboard shortcuts, and on macOS its own menu bar;
// - full screen with F11, the title bar and rail hidden.
//
// In a desktop's glass (theme/theme.dart's Glass) the title bar is clear over the backdrop (in
// Fluent 2, plain white in a light theme and plain black in a dark one), and
// the rail and the page sit on it as each desktop has them: Fluent 2's pages on a layer a shade
// lighter than the Mica beside the rail, macOS Tahoe's rail a pane of glass floating inside the
// window's edge, and Frosted Glass's rail a frosted pane down the side.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../api/resolve.dart';
import '../app/actions.dart';
import '../app/edge_tray.dart';
import '../app/links.dart';
import '../app/nav.dart';
import '../data/history.dart';
import '../data/store.dart';
import '../features/bug/bug_report.dart';
import '../features/history/history_page.dart';
import '../features/home/fixer.dart';
import '../features/home/home_page.dart';
import '../features/look/look_page.dart';
import '../features/sync/sync_page.dart';
import '../features/tour/tour.dart';
import '../features/update/update_bar.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'desktop.dart';
import 'screenshot.dart';

/// The desktop's main window: title bar, navigation rail (or bottom bar) and the pages.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() {
    return DesktopShellState();
  }
}

class DesktopShellState extends State<DesktopShell> with WindowListener {
  static DesktopShellState? current;

  /// For screenshots: drawn without a real window to ask (window_manager).
  static bool preview = false;

  String _page = 'home';
  Map<String, Object?> _arguments = const {};
  final Set<String> _builtPages = {'home'};
  bool _fullScreen = false;
  bool _maximized = false;
  String? _flash; // "Link copied", over the command bar for 1.5 s
  Timer? _flashTimer;
  final _content = GlobalKey();
  final _command = GlobalKey<_CommandBarState>();

  // The rail wide or collapsed, and History beside the cleaner or not: remembered.
  static const _railKey = 'uwufix.desk.rail';
  static const _paneKey = 'uwufix.desk.historyPane';
  double _width = 1280;

  /// Whether the rail shows names: as last chosen, or until then, on a window over 1300 px.
  bool get railWide {
    switch (Store.I.get(_railKey)) {
      case 'wide':
        return true;
      case 'narrow':
        return false;
      default:
        return _width > 1300;
    }
  }

  bool get historyPane {
    return Store.I.get(_paneKey) != 'hidden';
  }

  void toggleRail() {
    setState(() {
      if (railWide) {
        Store.I.put(_railKey, 'narrow');
      } else {
        Store.I.put(_railKey, 'wide');
      }
    });
  }

  void toggleHistoryPane() {
    setState(() {
      final hide = historyPane;
      if (hide) {
        Store.I.put(_paneKey, 'hidden');
      } else {
        Store.I.put(_paneKey, null);
      }
      // Put away while History is the page: the cleaner beside it becomes the page.
      if (hide && _page == 'history' && _width > 1024) {
        _page = 'home';
        AppNav.shown('home');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    current = this;
    if (!preview) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((maximized) {
        if (mounted) {
          setState(() {
            _maximized = maximized;
          });
        }
      });
    }
    AppNav.opener = (id, arguments) {
      setState(() {
        _page = id;
        _arguments = arguments;
        _builtPages.add(id);
      });
      AppNav.shown(id);
    };
    AppNav.reloaders['home'] = () {
      if (Fixer.I.cleaned == null) {
        return Future.value();
      }
      return Fixer.I.fix();
    };
    AppNav.reloaders['history'] = () async {
      History.changed.value++;
    };
  }

  @override
  void dispose() {
    if (!preview) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _maximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _maximized = false;
    });
  }

  @override
  void onWindowEnterFullScreen() {
    setState(() {
      _fullScreen = true;
    });
  }

  @override
  void onWindowLeaveFullScreen() {
    setState(() {
      _fullScreen = false;
    });
  }

  void flash(String text) {
    _flashTimer?.cancel();
    setState(() {
      _flash = text;
    });
    _flashTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _flash = null;
        });
      }
    });
  }

  /// The view's shareable address on the site.
  String get shareable {
    if (_page == 'home' && Fixer.I.input.text.trim().isNotEmpty) {
      return '$site/?url=${Uri.encodeComponent(Fixer.I.input.text.trim())}';
    }
    if (_page == 'sync' && SyncController.I.mode == 'host' && SyncController.I.code.isNotEmpty) {
      return SyncController.I.link;
    }
    return '$site/';
  }

  Future<void> copyLink() async {
    await Clipboard.setData(ClipboardData(text: shareable));
    flash('Link copied');
  }

  Future<void> screenshot({bool long = false}) async {
    final result = await takeScreenshot(_content, page: _page, long: long);
    if (result != null) {
      flash(result);
    } else {
      flash('Couldn’t take a screenshot');
    }
  }

  Future<void> toggleFull() async {
    await windowManager.setFullScreen(!await windowManager.isFullScreen());
  }

  Widget _pageWidget(String id, {required bool wide}) {
    switch (id) {
      case 'history':
        return const HistoryPage(pane: true);
      case 'sync':
        return SyncPage(joinCode: _arguments['join'] as String?, embedded: true, key: ValueKey('sync${_arguments['join']}'));
      case 'look':
        return const LookPage(embedded: true);
      default:
        return const HomePage();
    }
  }

  /// History beside the cleaner: History slides out to the left as it's put away, and back in,
  /// the cleaner widening and narrowing beside it. Put away, it can't be reached by Tab or a click.
  Widget _splitContent(BuildContext context, Fx palette, double width) {
    double paneWidth;
    if (width > 1300) {
      paneWidth = 400.0 + 1;
    } else {
      paneWidth = 360.0 + 1;
    }
    Duration slideTime;
    if (MediaQuery.of(context).disableAnimations) {
      slideTime = Duration.zero;
    } else {
      slideTime = const Duration(milliseconds: 280);
    }
    double shownWidth;
    if (historyPane) {
      shownWidth = paneWidth;
    } else {
      shownWidth = 0;
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRect(
        child: AnimatedContainer(
          duration: slideTime,
          curve: Curves.easeOutCubic,
          width: shownWidth,
          child: OverflowBox(
            alignment: Alignment.centerRight,
            minWidth: paneWidth,
            maxWidth: paneWidth,
            child: ExcludeFocus(
              excluding: !historyPane,
              child: IgnorePointer(
                ignoring: !historyPane,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: HistoryPage(pane: true, onHide: toggleHistoryPane)),
                  VerticalDivider(width: 1, color: palette.border),
                ]),
              ),
            ),
          ),
        ),
      ),
      Expanded(child: HomePage(showHistoryButton: !historyPane)),
    ]);
  }

  /// The rail beside the page on show, each laid out as the desktop's glass has them.
  Widget _railAndPage(BuildContext context, BoxConstraints constraints) {
    final palette = context.fx;
    final width = constraints.maxWidth;
    _width = width;
    final rail = width >= 720 && !_fullScreen;
    final split = width > 1024 && (_page == 'home' || (_page == 'history' && historyPane));
    Widget content;
    if (split) {
      content = _splitContent(context, palette, width);
    } else {
      // Pages built once and kept, so switching back keeps their place. Share history
      // only while it's on show: leaving it ends sharing.
      content = Stack(children: [
        for (final id in const ['home', 'history', 'look'])
          if (_builtPages.contains(id))
            Offstage(
              offstage: _page != id,
              child: TickerMode(enabled: _page == id, child: _pageWidget(id, wide: false)),
            ),
        if (_page == 'sync') _pageWidget('sync', wide: false),
      ]);
    }
    Widget body = RepaintBoundary(key: _content, child: Material(color: Theme.of(context).scaffoldBackgroundColor, child: content));
    Widget side = _Rail(page: _page, extended: railWide, onToggle: toggleRail);
    final glass = palette.glass;
    switch (glass) {
      case Glass.fluent:
        // The page on a layer over the Mica, its corner by the rail rounded.
        double cornerRadius;
        if (rail) {
          cornerRadius = glass!.control;
        } else {
          cornerRadius = 0;
        }
        body = DecoratedBox(
          decoration: ShapeDecoration(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(topLeft: Radius.circular(cornerRadius)),
              side: BorderSide(color: palette.border),
            ),
          ),
          child: body,
        );
      case Glass.tahoe:
        side = Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 0, 8),
          child: GlassPane(blur: !AppLook.I.backdrop, child: side),
        );
      case Glass.frosted:
        side = ColoredBox(color: palette.surface, child: side);
      case null:
        break;
    }
    final divider = glass == null || glass == Glass.frosted;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rail) side,
      if (rail && divider) VerticalDivider(width: 1, color: palette.border),
      Expanded(child: body),
    ]);
  }

  /// The navigation bar at the bottom, on a window under 720 px wide.
  Widget _bottomBar(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 720 && !_fullScreen;
    if (!narrow) {
      return const SizedBox.shrink();
    }
    return NavigationBar(
      selectedIndex: AppNav.pages.indexOf(_page).clamp(0, 3),
      onDestinationSelected: (index) {
        AppNav.showPage(AppNav.pages[index]);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.cleaning_services_outlined), label: 'Fix'),
        NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        NavigationDestination(icon: Icon(Icons.devices_outlined), label: 'Share'),
        NavigationDestination(icon: Icon(Icons.palette_outlined), label: 'Look'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Shortcuts(
      shell: this,
      child: Scaffold(
        body: Column(children: [
          if (!_fullScreen) _TitleBar(shell: this, maximized: _maximized, command: _command, flash: _flash),
          const AppUpdateBar(),
          Expanded(
            child: LayoutBuilder(builder: _railAndPage),
          ),
          LayoutBuilder(builder: (context, _) {
            return _bottomBar(context);
          }),
        ]),
      ),
    );
  }
}

/// The navigation rail: its collapse toggle, the pages, and the app's other buttons below them.
class _Rail extends StatelessWidget {
  const _Rail({required this.page, required this.extended, required this.onToggle});
  final String page;
  final bool extended;
  final VoidCallback onToggle;

  /// The collapsed rail's width (Material 3's), which the buttons above and below the pages keep
  /// to either way, so they line up with the pages' icons.
  static const _narrow = 80.0;
  static const _wide = 256.0; // NavigationRail's minExtendedWidth

  /// The collapse or expand button at the top, moving with the rail as it opens and closes.
  Widget _toggleButton(BuildContext context) {
    final open = NavigationRail.extendedAnimation(context);
    String tooltip;
    IconData icon;
    if (extended) {
      tooltip = 'Collapse sidebar (Ctrl+B)';
      icon = Icons.menu_open;
    } else {
      tooltip = 'Expand sidebar (Ctrl+B)';
      icon = Icons.menu;
    }
    return AnimatedBuilder(
      animation: open,
      builder: (context, _) {
        return SizedBox(
          width: _narrow + (_wide - _narrow) * open.value,
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: _narrow,
              child: Center(
                child: IconButton(
                  tooltip: tooltip,
                  onPressed: onToggle,
                  icon: Icon(icon),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The buttons below the pages, moving with the rail as it opens and closes.
  Widget _actions(BuildContext context) {
    final open = NavigationRail.extendedAnimation(context);
    return AnimatedBuilder(
      animation: open,
      builder: (context, _) {
        Widget item(Widget icon, String label, VoidCallback onTap) {
          return _RailAction(icon: icon, label: label, onTap: onTap, open: open.value);
        }

        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TourTarget(
            id: 'rail.tour',
            child: item(const Icon(Icons.help_outline), 'Show me around', () {
              showTourPicker(context);
            }),
          ),
          item(const Icon(Icons.bug_report_outlined), 'Report a bug', openBugReport),
          item(const SvgIcon(telegramSvg, size: 20), 'Telegram Bot', () {
            openLink(telegramUrl);
          }),
          item(const SvgIcon(discordSvg, size: 20), 'Invite Discord Bot', () {
            openLink(discordUrl);
          }),
          item(const Icon(Icons.coffee_outlined), 'Buy me a coffee', () {
            openLink(coffeeUrl);
          }),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    // History's count in the brand colour, as the site's is: a count, not an alert (Badge's
    // default is red).
    Color badge;
    Color? background;
    if (palette.uwu) {
      badge = palette.brandFillStrong;
      background = palette.surface;
    } else {
      badge = Theme.of(context).colorScheme.primary;
    }
    Color badgeInk;
    if (badge.computeLuminance() > 0.4) {
      badgeInk = const Color(0xFF121815);
    } else {
      badgeInk = Colors.white;
    }
    NavigationRailLabelType labelType;
    if (extended) {
      labelType = NavigationRailLabelType.none;
    } else {
      labelType = NavigationRailLabelType.all;
    }
    final historyIcon = TourTarget(
      id: 'rail.history',
      child: ValueListenableBuilder(
        valueListenable: History.changed,
        builder: (_, _, _) {
          return Badge.count(
            count: History.load().length,
            isLabelVisible: History.load().isNotEmpty,
            backgroundColor: badge,
            textColor: badgeInk,
            child: const Icon(Icons.history),
          );
        },
      ),
    );
    return NavigationRail(
      extended: extended,
      backgroundColor: background,
      selectedIndex: AppNav.pages.indexOf(page),
      onDestinationSelected: (index) {
        AppNav.showPage(AppNav.pages[index]);
      },
      labelType: labelType,
      // The toggle and the buttons below the pages move with the rail as it opens and closes
      // (its own animation), keeping in line with the pages' icons.
      leading: Builder(builder: _toggleButton),
      destinations: [
        const NavigationRailDestination(icon: Icon(Icons.cleaning_services_outlined), selectedIcon: Icon(Icons.cleaning_services), label: Text('Fix')),
        NavigationRailDestination(
          icon: historyIcon,
          label: const Text('History'),
        ),
        const NavigationRailDestination(icon: Icon(Icons.devices_outlined), selectedIcon: Icon(Icons.devices), label: Text('Share history')),
        const NavigationRailDestination(icon: Icon(Icons.palette_outlined), selectedIcon: Icon(Icons.palette), label: Text('Look')),
      ],
      // Below the pages: each with its name beside it while the rail is open, as the pages
      // have, and just its icon (and a tooltip) while it's collapsed.
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Builder(builder: _actions),
          ),
        ),
      ),
    );
  }
}

/// One of the rail's buttons below its pages: its icon in line with the pages' icons, and its
/// name beside it, fading in as the rail opens (open: 0 collapsed, 1 wide).
class _RailAction extends StatelessWidget {
  const _RailAction({required this.icon, required this.label, required this.onTap, required this.open});
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final double open;

  static const _inset = 12.0; // each side of the button's highlight
  static const _iconBox = _Rail._narrow - _inset * 2; // the icon centred where the pages' are
  static const _labelAt = _Rail._narrow - _inset; // the name starts where the pages' names do

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rail = NavigationRailTheme.of(context);
    Color ink;
    if (rail.unselectedIconTheme?.color != null) {
      ink = rail.unselectedIconTheme!.color!;
    } else {
      ink = theme.colorScheme.onSurfaceVariant;
    }
    TextStyle? style;
    if (rail.unselectedLabelTextStyle != null) {
      style = rail.unselectedLabelTextStyle;
    } else {
      style = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface);
    }
    final width = _Rail._narrow + (_Rail._wide - _Rail._narrow) * open;
    final inner = width - _inset * 2;
    // The name only once there's room for some of it.
    final named = inner > _labelAt + 24;
    final button = SizedBox(
      width: width,
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _inset, vertical: 2),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Stack(children: [
              Positioned(left: 0, top: 0, bottom: 0, width: _iconBox, child: Center(child: IconTheme.merge(data: IconThemeData(color: ink, size: 24), child: icon))),
              if (named)
                Positioned(
                  left: _labelAt,
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Opacity(
                      opacity: ((open - 0.3) / 0.7).clamp(0.0, 1.0),
                      child: Text(label, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
    // Collapsed, the name is a tooltip instead; open, it's on the button.
    if (open < 0.5) {
      return Tooltip(message: label, child: button);
    }
    return Semantics(button: true, child: button);
  }
}

/// The title bar: Back, Forward, Reload, the command bar, the page's own buttons, the update
/// button once one's downloaded, and the window's buttons (not on macOS, which has its own).
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.shell, required this.maximized, required this.command, required this.flash});
  final DesktopShellState shell;
  final bool maximized;
  final GlobalKey<_CommandBarState> command;
  final String? flash;

  /// Fluent 2: plain white in a light theme and plain black in a dark one. The other desktop
  /// glass: clear, over the backdrop, as macOS's title bar is.
  Color _barColor(BuildContext context, Fx palette) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (palette.glass) {
      case Glass.fluent:
        if (dark) {
          return Colors.black;
        }
        return Colors.white;
      case null:
        if (palette.uwu) {
          return palette.brandFill;
        }
        return Theme.of(context).colorScheme.surfaceContainer;
      default:
        return Colors.transparent;
    }
  }

  /// The update button while an update is downloaded and ready to install.
  Widget _updateButton() {
    if (AppUpdate.I.state != 'ready') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E8E3E), foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
        onPressed: () {
          Desktop.updater?.install();
        },
        icon: const Icon(Icons.system_update_alt, size: 16),
        label: const Text('Update'),
      ),
    );
  }

  /// Minimise, maximise or restore, and close, on Windows and Linux; on macOS just a gap.
  List<Widget> _windowButtons(Color ink) {
    if (Desktop.mac) {
      return const [SizedBox(width: 8)];
    }
    IconData maximizeIcon;
    String maximizeTooltip;
    if (maximized) {
      maximizeIcon = Icons.filter_none;
      maximizeTooltip = 'Restore';
    } else {
      maximizeIcon = Icons.crop_square;
      maximizeTooltip = 'Maximise';
    }
    return [
      const SizedBox(width: 6),
      _WinButton(icon: Icons.remove, ink: ink, onTap: windowManager.minimize, tooltip: 'Minimise'),
      _WinButton(
        icon: maximizeIcon,
        ink: ink,
        onTap: () async {
          if (maximized) {
            await windowManager.unmaximize();
          } else {
            await windowManager.maximize();
          }
        },
        tooltip: maximizeTooltip,
      ),
      _WinButton(icon: Icons.close, ink: ink, onTap: Desktop.hide, tooltip: 'Close', close: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    final bar = _barColor(context, palette);
    Color ink;
    if (bar == Colors.transparent) {
      ink = palette.ink;
    } else if (bar.computeLuminance() > 0.45) {
      ink = const Color(0xFF121815);
    } else {
      ink = Colors.white;
    }
    Widget titleButton(IconData icon, String tooltip, VoidCallback? onTap) {
      return Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: SizedBox(
          width: 34,
          height: 32,
          child: IconButton(padding: EdgeInsets.zero, iconSize: 18, color: ink, disabledColor: ink.withValues(alpha: 0.35), onPressed: onTap, icon: Icon(icon)),
        ),
      );
    }

    // On macOS, room for its own window buttons at the left.
    double leadingGap;
    if (Desktop.mac) {
      leadingGap = 78;
    } else {
      leadingGap = 8;
    }
    String historyPaneTooltip;
    if (shell.historyPane) {
      historyPaneTooltip = 'Hide history (Ctrl+Shift+H)';
    } else {
      historyPaneTooltip = 'Show history beside (Ctrl+Shift+H)';
    }
    return Container(
      height: 40,
      color: bar,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            child: const DragToMoveArea(child: SizedBox.expand()),
          ),
        ),
        Row(children: [
          SizedBox(width: leadingGap),
          ValueListenableBuilder(
            valueListenable: AppNav.canGo,
            builder: (_, canGo, _) {
              final (canGoBack, canGoForward) = canGo;
              VoidCallback? onBack;
              VoidCallback? onForward;
              if (canGoBack) {
                onBack = AppNav.back;
              }
              if (canGoForward) {
                onForward = AppNav.forward;
              }
              return Row(children: [
                titleButton(Icons.arrow_back, 'Back (Alt+Left)', onBack),
                titleButton(Icons.arrow_forward, 'Forward (Alt+Right)', onForward),
              ]);
            },
          ),
          ValueListenableBuilder(
            valueListenable: AppNav.reloading,
            builder: (_, busy, _) {
              if (busy) {
                return SizedBox(width: 34, height: 32, child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ink))));
              }
              return titleButton(Icons.refresh, 'Reload (F5)', AppNav.reload);
            },
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _CommandBar(key: command, ink: ink, flash: flash),
              ),
            ),
          ),
          // History beside the cleaner, on a window wide enough for it, on the pages it's beside.
          if (MediaQuery.sizeOf(context).width > 1024 && (AppNav.page.value == 'home' || AppNav.page.value == 'history'))
            titleButton(Icons.vertical_split_outlined, historyPaneTooltip, shell.toggleHistoryPane),
          titleButton(Icons.link, 'Copy link (Ctrl+Shift+C)', shell.copyLink),
          titleButton(Icons.photo_camera_outlined, 'Screenshot', () {
            shell.screenshot();
          }),
          titleButton(Icons.view_day_outlined, 'Long screenshot', () {
            shell.screenshot(long: true);
          }),
          ListenableBuilder(
            listenable: AppUpdate.I,
            builder: (_, _) {
              return _updateButton();
            },
          ),
          ..._windowButtons(ink),
        ]),
      ]),
    );
  }
}

/// Windows' and Linux's window buttons, full bar height and 46 px wide, close red on hover.
class _WinButton extends StatefulWidget {
  const _WinButton({required this.icon, required this.ink, required this.onTap, required this.tooltip, this.close = false});
  final IconData icon;
  final Color ink;
  final VoidCallback onTap;
  final String tooltip;
  final bool close;

  @override
  State<_WinButton> createState() {
    return _WinButtonState();
  }
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Color background;
    if (!_hover) {
      background = Colors.transparent;
    } else if (widget.close) {
      background = const Color(0xFFE81123);
    } else {
      background = widget.ink.withValues(alpha: 0.1);
    }
    Color iconColor;
    if (_hover && widget.close) {
      iconColor = Colors.white;
    } else {
      iconColor = widget.ink;
    }
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() {
            _hover = true;
          });
        },
        onExit: (_) {
          setState(() {
            _hover = false;
          });
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 40,
            color: background,
            child: Icon(widget.icon, size: 16, color: iconColor),
          ),
        ),
      ),
    );
  }
}

/// The command bar: at rest the page's name; clicked, or Ctrl+K, a live search of the app's
/// commands and your history. A link pasted there and Enter cleans it (a uwu://fix or site link is
/// opened as one); Esc closes it.
class _CommandBar extends StatefulWidget {
  const _CommandBar({super.key, required this.ink, this.flash});
  final Color ink;
  final String? flash;

  @override
  State<_CommandBar> createState() {
    return _CommandBarState();
  }
}

class _Command {
  const _Command(this.label, this.icon, this.run, [this.detail]);
  final String label;
  final IconData icon;
  final VoidCallback run;
  final String? detail;
}

class _CommandBarState extends State<_CommandBar> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  OverlayEntry? _overlay;
  int _selected = 0;

  static const _titles = {'home': 'Fix a link', 'history': 'History', 'sync': 'Share history', 'look': 'Look'};

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _open();
      } else {
        Timer(const Duration(milliseconds: 150), _close);
      }
    });
    _field.addListener(() {
      _selected = 0;
      _overlay?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _close();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void focus() => _focus.requestFocus();

  List<_Command> get _commands {
    final q = _field.text.trim().toLowerCase();
    final all = <_Command>[
      _Command('Fix copied link', Icons.content_paste, fixCopied),
      _Command('Fix a link', Icons.cleaning_services_outlined, () => AppNav.showPage('home')),
      _Command('History', Icons.history, () => AppNav.showPage('history')),
      _Command('Share history', Icons.devices_outlined, () => AppNav.showPage('sync')),
      _Command('Look', Icons.palette_outlined, () => AppNav.showPage('look')),
      _Command('Show me around', Icons.help_outline, () => showTourPicker(AppNav.context!)),
      _Command('Report a bug', Icons.bug_report_outlined, openBugReport),
      _Command('Add a Fix a link widget', Icons.widgets_outlined, () => runTask('widget')),
      _Command('Make it yours', Icons.tune, () => runTask('welcome')),
      _Command('Check for updates', Icons.system_update_alt, () => AppUpdate.I.check(asked: true)),
      _Command('Full screen', Icons.fullscreen, () => DesktopShellState.current?.toggleFull()),
      _Command(DesktopShellState.current?.railWide ?? true ? 'Collapse sidebar' : 'Expand sidebar', Icons.menu_open, () => DesktopShellState.current?.toggleRail()),
      _Command(DesktopShellState.current?.historyPane ?? true ? 'Hide history beside the cleaner' : 'Show history beside the cleaner', Icons.vertical_split_outlined, () => DesktopShellState.current?.toggleHistoryPane()),
    ];
    final out = q.isEmpty ? all : all.where((c) => c.label.toLowerCase().contains(q)).toList();
    if (q.isNotEmpty) {
      for (final e in History.load()) {
        if (out.length > 12) break;
        if ('${e.title ?? ''} ${e.cleaned} ${e.original}'.toLowerCase().contains(q)) {
          out.add(_Command(e.title ?? e.cleaned, Icons.link, () {
            AppNav.showPage('home');
            HistoryPage.load(e);
          }, e.cleaned));
        }
      }
    }
    return out;
  }

  void _run(String text) {
    final t = text.trim();
    _field.clear();
    _focus.unfocus();
    // A link: cleaned (or opened, if it's the site's or a uwu://fix link).
    if (t.isNotEmpty && (t.contains('://') || t.contains('.')) && Links.open(t)) return;
    final list = _commands;
    if (list.isNotEmpty) list[_selected.clamp(0, list.length - 1)].run();
  }

  void _open() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: (context) {
      final list = _commands;
      final fx = context.fx;
      // In a desktop's glass, Acrylic: what's under it blurred, the window's colour over that.
      Widget surface({required Widget child}) => fx.glass != null
          ? GlassPane(radius: fx.glass!.card.clamp(8, 16), color: fx.bg.withValues(alpha: 0.78), child: child)
          : Material(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
              color: fx.uwu ? Color.alphaBlend(fx.surfaceStrong, Theme.of(context).scaffoldBackgroundColor) : Theme.of(context).colorScheme.surfaceContainerHigh,
              child: child,
            );
      return Positioned(
        width: 520,
        child: CompositedTransformFollower(
          link: _link,
          offset: const Offset(0, 36),
          showWhenUnlinked: false,
          child: surface(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 6), children: [
                if (_field.text.trim().contains('.'))
                  ListTile(dense: true, leading: const Icon(Icons.shield_outlined), title: const Text('Press Enter to clean this link'), subtitle: Text(_field.text.trim(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                for (var i = 0; i < list.length; i++)
                  ListTile(
                    dense: true,
                    selected: i == _selected,
                    leading: Icon(list[i].icon, size: 20),
                    title: Text(list[i].label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: list[i].detail == null ? null : Text(list[i].detail!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      _field.clear();
                      _focus.unfocus();
                      list[i].run();
                    },
                  ),
              ]),
            ),
          ),
        ),
      );
    });
    Overlay.of(context).insert(_overlay!);
  }

  void _close() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: SizedBox(
        height: 30,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              _field.clear();
              _focus.unfocus();
            },
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              _selected = (_selected + 1).clamp(0, _commands.length - 1);
              _overlay?.markNeedsBuild();
            },
            const SingleActivator(LogicalKeyboardKey.arrowUp): () {
              _selected = (_selected - 1).clamp(0, _commands.length - 1);
              _overlay?.markNeedsBuild();
            },
          },
          child: ValueListenableBuilder(
            valueListenable: AppNav.page,
            builder: (context, page, _) {
              // In a desktop's glass, a pane of it (a capsule in macOS Tahoe's).
              final fx = context.fx;
              final g = fx.glass;
              final radius = BorderRadius.circular(g == null ? 8 : (g.control >= 999 ? 15 : g.control));
              final rest = g == null ? BorderSide.none : BorderSide(color: fx.border);
              return TextField(
              controller: _field,
              focusNode: _focus,
              onSubmitted: _run,
              style: TextStyle(color: widget.ink, fontSize: 13.5),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: g == null ? widget.ink.withValues(alpha: 0.08) : fx.surfaceStrong,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                prefixIcon: Icon(Icons.search, size: 16, color: widget.ink.withValues(alpha: 0.7)),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                hintText: widget.flash ?? '${_titles[page] ?? 'uwuFix'}  ·  Ctrl+K to search, or paste a link',
                hintStyle: TextStyle(color: widget.ink.withValues(alpha: widget.flash == null ? 0.65 : 1), fontSize: 13),
                border: OutlineInputBorder(borderRadius: radius, borderSide: rest),
                enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: rest),
                focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: g == null ? widget.ink.withValues(alpha: 0.4) : fx.brandInk)),
              ),
            );
            },
          ),
        ),
      ),
    );
  }
}

/// The desktop's keyboard shortcuts, and on macOS the menu bar that names them.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.shell, required this.child});
  final DesktopShellState shell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    SingleActivator key(LogicalKeyboardKey k, {bool shift = false}) => SingleActivator(k, control: !mac, meta: mac, shift: shift);
    void command() => shell._command.currentState?.focus();
    final bindings = <ShortcutActivator, VoidCallback>{
      key(LogicalKeyboardKey.keyK): command,
      key(LogicalKeyboardKey.keyF): command,
      key(LogicalKeyboardKey.keyL): command,
      const SingleActivator(LogicalKeyboardKey.f6): command,
      key(LogicalKeyboardKey.keyC, shift: true): shell.copyLink,
      key(LogicalKeyboardKey.keyB): shell.toggleRail,
      key(LogicalKeyboardKey.keyH, shift: true): shell.toggleHistoryPane,
      SingleActivator(LogicalKeyboardKey.arrowLeft, alt: !mac): AppNav.back,
      SingleActivator(LogicalKeyboardKey.arrowRight, alt: !mac): AppNav.forward,
      if (mac) key(LogicalKeyboardKey.bracketLeft): AppNav.back,
      if (mac) key(LogicalKeyboardKey.bracketRight): AppNav.forward,
      const SingleActivator(LogicalKeyboardKey.f5): AppNav.reload,
      key(LogicalKeyboardKey.keyR): AppNav.reload,
      key(LogicalKeyboardKey.comma): () => AppNav.showPage('look'),
      key(LogicalKeyboardKey.keyW): () {
        final nav = AppNav.navigatorKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.maybePop();
        } else {
          Desktop.hide();
        }
      },
      const SingleActivator(LogicalKeyboardKey.f11): shell.toggleFull,
      if (mac) const SingleActivator(LogicalKeyboardKey.keyF, control: true, meta: true): shell.toggleFull,
      const SingleActivator(LogicalKeyboardKey.escape): () async {
        if (await windowManager.isFullScreen()) await windowManager.setFullScreen(false);
      },
    };
    Widget out = CallbackShortcuts(bindings: bindings, child: Focus(autofocus: true, child: child));
    if (mac) {
      out = PlatformMenuBar(menus: [
        PlatformMenu(label: 'uwuFix', menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(label: 'Make it yours…', onSelected: () => runTask('welcome')),
            PlatformMenuItem(label: 'Settings…', shortcut: const SingleActivator(LogicalKeyboardKey.comma, meta: true), onSelected: () => AppNav.showPage('look')),
            PlatformMenuItem(label: 'Check for updates…', onSelected: () => AppUpdate.I.check(asked: true)),
          ]),
          PlatformMenuItem(label: 'Hide uwuFix', shortcut: const SingleActivator(LogicalKeyboardKey.keyH, meta: true), onSelected: Desktop.hide),
          PlatformMenuItem(label: 'Quit uwuFix', shortcut: const SingleActivator(LogicalKeyboardKey.keyQ, meta: true), onSelected: Desktop.quit),
        ]),
        PlatformMenu(label: 'File', menus: [
          PlatformMenuItem(label: 'Fix copied link', onSelected: fixCopied),
          PlatformMenuItem(label: 'Add a Fix a link widget', onSelected: () => runTask('widget')),
          PlatformMenuItem(label: 'Copy link', shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true), onSelected: shell.copyLink),
          PlatformMenuItem(label: 'Screenshot', onSelected: () => shell.screenshot()),
          PlatformMenuItem(label: 'Long screenshot', onSelected: () => shell.screenshot(long: true)),
          PlatformMenuItem(label: 'Close window', shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true), onSelected: Desktop.hide),
        ]),
        const PlatformMenu(label: 'Edit', menus: [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.servicesSubmenu),
        ]),
        PlatformMenu(label: 'View', menus: [
          PlatformMenuItem(label: 'Search', shortcut: const SingleActivator(LogicalKeyboardKey.keyK, meta: true), onSelected: command),
          PlatformMenuItem(label: 'Reload', shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true), onSelected: AppNav.reload),
          PlatformMenuItem(label: 'History', onSelected: () => AppNav.showPage('history')),
          PlatformMenuItem(label: 'Share history', onSelected: () => AppNav.showPage('sync')),
          PlatformMenuItem(label: 'Full screen', shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true, control: true), onSelected: shell.toggleFull),
          PlatformMenuItem(label: 'Collapse or expand sidebar', shortcut: const SingleActivator(LogicalKeyboardKey.keyB, meta: true), onSelected: shell.toggleRail),
          PlatformMenuItem(label: 'Show or hide history beside', shortcut: const SingleActivator(LogicalKeyboardKey.keyH, meta: true, shift: true), onSelected: shell.toggleHistoryPane),
        ]),
        PlatformMenu(label: 'Window', menus: [
          PlatformMenuItem(label: 'Minimise', shortcut: const SingleActivator(LogicalKeyboardKey.keyM, meta: true), onSelected: windowManager.minimize),
          PlatformMenuItem(label: 'Back', shortcut: const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true), onSelected: AppNav.back),
          PlatformMenuItem(label: 'Forward', shortcut: const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true), onSelected: AppNav.forward),
        ]),
        PlatformMenu(label: 'Help', menus: [
          PlatformMenuItem(label: 'Show me around', onSelected: () => showTourPicker(AppNav.context!)),
          PlatformMenuItem(label: 'Report a bug…', onSelected: openBugReport),
          PlatformMenuItem(label: 'uwuFix on GitHub', onSelected: () => openLink('https://github.com/augy-studios/fixup-links')),
        ]),
      ], child: out);
    }
    return out;
  }
}

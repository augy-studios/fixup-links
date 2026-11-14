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
import 'desktop.dart';
import 'screenshot.dart';

class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => DesktopShellState();
}

class DesktopShellState extends State<DesktopShell> with WindowListener {
  static DesktopShellState? current;

  /// For screenshots: drawn without a real window to ask (window_manager).
  static bool preview = false;

  String _page = 'home';
  Map<String, Object?> _args = const {};
  final Set<String> _built = {'home'};
  bool _full = false;
  bool _maximized = false;
  String? _flash; // "Link copied", over the command bar for 1.5 s
  Timer? _flashTimer;
  final _content = GlobalKey();
  final _command = GlobalKey<_CommandBarState>();

  // The rail wide or collapsed, and History beside the cleaner or not: remembered.
  static const _railKey = 'uwufix.desk.rail';
  static const _paneKey = 'uwufix.desk.historyPane';
  double _width = 1280;
  bool get railWide => switch (Store.I.get(_railKey)) { 'wide' => true, 'narrow' => false, _ => _width > 1300 };
  bool get historyPane => Store.I.get(_paneKey) != 'hidden';

  void toggleRail() => setState(() => Store.I.put(_railKey, railWide ? 'narrow' : 'wide'));

  void toggleHistoryPane() => setState(() {
        final hide = historyPane;
        Store.I.put(_paneKey, hide ? 'hidden' : null);
        // Put away while History is the page: the cleaner beside it becomes the page.
        if (hide && _page == 'history' && _width > 1024) {
          _page = 'home';
          AppNav.shown('home');
        }
      });

  @override
  void initState() {
    super.initState();
    current = this;
    if (!preview) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((v) => mounted ? setState(() => _maximized = v) : null);
    }
    AppNav.opener = (id, args) {
      setState(() {
        _page = id;
        _args = args;
        _built.add(id);
      });
      AppNav.shown(id);
    };
    AppNav.reloaders['home'] = () => Fixer.I.cleaned == null ? Future.value() : Fixer.I.fix();
    AppNav.reloaders['history'] = () async => History.changed.value++;
  }

  @override
  void dispose() {
    if (!preview) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowEnterFullScreen() => setState(() => _full = true);
  @override
  void onWindowLeaveFullScreen() => setState(() => _full = false);

  void flash(String text) {
    _flashTimer?.cancel();
    setState(() => _flash = text);
    _flashTimer = Timer(const Duration(milliseconds: 1500), () => mounted ? setState(() => _flash = null) : null);
  }

  /// The view's shareable address on the site.
  String get shareable {
    if (_page == 'home' && Fixer.I.input.text.trim().isNotEmpty) return '$site/?url=${Uri.encodeComponent(Fixer.I.input.text.trim())}';
    if (_page == 'sync' && SyncController.I.mode == 'host' && SyncController.I.code.isNotEmpty) return SyncController.I.link;
    return '$site/';
  }

  Future<void> copyLink() async {
    await Clipboard.setData(ClipboardData(text: shareable));
    flash('Link copied');
  }

  Future<void> screenshot({bool long = false}) async {
    final r = await takeScreenshot(_content, page: _page, long: long);
    flash(r ?? 'Couldn’t take a screenshot');
  }

  Future<void> toggleFull() async => windowManager.setFullScreen(!await windowManager.isFullScreen());

  Widget _pageWidget(String id, {required bool wide}) => switch (id) {
        'history' => const HistoryPage(pane: true),
        'sync' => SyncPage(joinCode: _args['join'] as String?, embedded: true, key: ValueKey('sync${_args['join']}')),
        'look' => const LookPage(embedded: true),
        _ => const HomePage(),
      };

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    return _Shortcuts(
      shell: this,
      child: Scaffold(
        body: Column(children: [
          if (!_full) _TitleBar(shell: this, maximized: _maximized, command: _command, flash: _flash),
          const AppUpdateBar(),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              _width = w;
              final rail = w >= 720 && !_full;
              final split = w > 1024 && (_page == 'home' || (_page == 'history' && historyPane));
              Widget content;
              if (split) {
                // History slides out to the left as it's put away, and back in, the cleaner
                // widening and narrowing beside it. Put away, it can't be reached by Tab or a click.
                final paneWidth = (w > 1300 ? 400.0 : 360.0) + 1;
                content = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ClipRect(
                    child: AnimatedContainer(
                      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      width: historyPane ? paneWidth : 0,
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
                              VerticalDivider(width: 1, color: fx.border),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: HomePage(showHistoryButton: !historyPane)),
                ]);
              } else {
                // Pages built once and kept, so switching back keeps their place. Share history
                // only while it's on show: leaving it ends sharing.
                content = Stack(children: [
                  for (final id in const ['home', 'history', 'look'])
                    if (_built.contains(id))
                      Offstage(
                        offstage: _page != id,
                        child: TickerMode(enabled: _page == id, child: _pageWidget(id, wide: false)),
                      ),
                  if (_page == 'sync') _pageWidget('sync', wide: false),
                ]);
              }
              final body = RepaintBoundary(key: _content, child: Material(color: Theme.of(context).scaffoldBackgroundColor, child: content));
              return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (rail) _Rail(page: _page, extended: railWide, onToggle: toggleRail),
                if (rail) VerticalDivider(width: 1, color: fx.border),
                Expanded(child: body),
              ]);
            }),
          ),
          LayoutBuilder(builder: (context, c) {
            final narrow = MediaQuery.sizeOf(context).width < 720 && !_full;
            if (!narrow) return const SizedBox.shrink();
            return NavigationBar(
              selectedIndex: AppNav.pages.indexOf(_page).clamp(0, 3),
              onDestinationSelected: (i) => AppNav.showPage(AppNav.pages[i]),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.cleaning_services_outlined), label: 'Fix'),
                NavigationDestination(icon: Icon(Icons.history), label: 'History'),
                NavigationDestination(icon: Icon(Icons.devices_outlined), label: 'Share'),
                NavigationDestination(icon: Icon(Icons.palette_outlined), label: 'Look'),
              ],
            );
          }),
        ]),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.page, required this.extended, required this.onToggle});
  final String page;
  final bool extended;
  final VoidCallback onToggle;

  /// The collapsed rail's width (Material 3's), which the buttons above and below the pages keep
  /// to either way, so they line up with the pages' icons.
  static const _narrow = 80.0;
  static const _wide = 256.0; // NavigationRail's minExtendedWidth

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    // History's count in the brand colour, as the site's is: a count, not an alert (Badge's
    // default is red).
    final badge = fx.uwu ? fx.brandFillStrong : Theme.of(context).colorScheme.primary;
    final badgeInk = badge.computeLuminance() > 0.4 ? const Color(0xFF121815) : Colors.white;
    return NavigationRail(
      extended: extended,
      backgroundColor: fx.uwu ? fx.surface : null,
      selectedIndex: AppNav.pages.indexOf(page),
      onDestinationSelected: (i) => AppNav.showPage(AppNav.pages[i]),
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      // The toggle and the buttons below the pages move with the rail as it opens and closes
      // (its own animation), keeping in line with the pages' icons.
      leading: Builder(
        builder: (context) {
          final open = NavigationRail.extendedAnimation(context);
          return AnimatedBuilder(
            animation: open,
            builder: (context, _) => SizedBox(
              width: _narrow + (_wide - _narrow) * open.value,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: _narrow,
                  child: Center(
                    child: IconButton(
                      tooltip: extended ? 'Collapse sidebar (Ctrl+B)' : 'Expand sidebar (Ctrl+B)',
                      onPressed: onToggle,
                      icon: Icon(extended ? Icons.menu_open : Icons.menu),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      destinations: [
        const NavigationRailDestination(icon: Icon(Icons.cleaning_services_outlined), selectedIcon: Icon(Icons.cleaning_services), label: Text('Fix')),
        NavigationRailDestination(
          icon: TourTarget(id: 'rail.history', child: ValueListenableBuilder(valueListenable: History.changed, builder: (_, _, _) => Badge.count(count: History.load().length, isLabelVisible: History.load().isNotEmpty, backgroundColor: badge, textColor: badgeInk, child: const Icon(Icons.history)))),
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
            child: Builder(
              builder: (context) {
                final open = NavigationRail.extendedAnimation(context);
                return AnimatedBuilder(
                  animation: open,
                  builder: (context, _) {
                    Widget item(Widget icon, String label, VoidCallback onTap) => _RailAction(icon: icon, label: label, onTap: onTap, open: open.value);
                    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TourTarget(id: 'rail.tour', child: item(const Icon(Icons.help_outline), 'Show me around', () => showTourPicker(context))),
                      item(const Icon(Icons.bug_report_outlined), 'Report a bug', openBugReport),
                      item(const SvgIcon(telegramSvg, size: 20), 'Telegram Bot', () => openLink(telegramUrl)),
                      item(const SvgIcon(discordSvg, size: 20), 'Invite Discord Bot', () => openLink(discordUrl)),
                      item(const Icon(Icons.coffee_outlined), 'Buy me a coffee', () => openLink(coffeeUrl)),
                    ]);
                  },
                );
              },
            ),
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
    final ink = rail.unselectedIconTheme?.color ?? theme.colorScheme.onSurfaceVariant;
    final style = rail.unselectedLabelTextStyle ?? theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface);
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
    return open < 0.5 ? Tooltip(message: label, child: button) : Semantics(button: true, child: button);
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.shell, required this.maximized, required this.command, required this.flash});
  final DesktopShellState shell;
  final bool maximized;
  final GlobalKey<_CommandBarState> command;
  final String? flash;

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    final scheme = Theme.of(context).colorScheme;
    final bar = fx.uwu ? fx.brandFill : scheme.surfaceContainer;
    final ink = bar.computeLuminance() > 0.45 ? const Color(0xFF121815) : Colors.white;
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 400),
          child: SizedBox(
            width: 34,
            height: 32,
            child: IconButton(padding: EdgeInsets.zero, iconSize: 18, color: ink, disabledColor: ink.withValues(alpha: 0.35), onPressed: onTap, icon: Icon(icon)),
          ),
        );
    return Container(
      height: 40,
      color: bar,
      child: Stack(children: [
        Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onDoubleTap: () async => await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize(), child: const DragToMoveArea(child: SizedBox.expand()))),
        Row(children: [
          SizedBox(width: Desktop.mac ? 78 : 8),
          ValueListenableBuilder(
            valueListenable: AppNav.canGo,
            builder: (_, can, _) => Row(children: [
              btn(Icons.arrow_back, 'Back (Alt+Left)', can.$1 ? AppNav.back : null),
              btn(Icons.arrow_forward, 'Forward (Alt+Right)', can.$2 ? AppNav.forward : null),
            ]),
          ),
          ValueListenableBuilder(
            valueListenable: AppNav.reloading,
            builder: (_, busy, _) => busy
                ? SizedBox(width: 34, height: 32, child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ink))))
                : btn(Icons.refresh, 'Reload (F5)', AppNav.reload),
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
            btn(Icons.vertical_split_outlined, shell.historyPane ? 'Hide history (Ctrl+Shift+H)' : 'Show history beside (Ctrl+Shift+H)', shell.toggleHistoryPane),
          btn(Icons.link, 'Copy link (Ctrl+Shift+C)', shell.copyLink),
          btn(Icons.photo_camera_outlined, 'Screenshot', () => shell.screenshot()),
          btn(Icons.view_day_outlined, 'Long screenshot', () => shell.screenshot(long: true)),
          ListenableBuilder(
            listenable: AppUpdate.I,
            builder: (_, _) => AppUpdate.I.state == 'ready'
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E8E3E), foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                      onPressed: () => Desktop.updater?.install(),
                      icon: const Icon(Icons.system_update_alt, size: 16),
                      label: const Text('Update'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (!Desktop.mac) ...[
            const SizedBox(width: 6),
            _WinButton(icon: Icons.remove, ink: ink, onTap: windowManager.minimize, tip: 'Minimise'),
            _WinButton(icon: maximized ? Icons.filter_none : Icons.crop_square, ink: ink, onTap: () async => maximized ? windowManager.unmaximize() : windowManager.maximize(), tip: maximized ? 'Restore' : 'Maximise'),
            _WinButton(icon: Icons.close, ink: ink, onTap: Desktop.hide, tip: 'Close', close: true),
          ] else
            const SizedBox(width: 8),
        ]),
      ]),
    );
  }
}

/// Windows' and Linux's window buttons, full bar height and 46 px wide, close red on hover.
class _WinButton extends StatefulWidget {
  const _WinButton({required this.icon, required this.ink, required this.onTap, required this.tip, this.close = false});
  final IconData icon;
  final Color ink;
  final VoidCallback onTap;
  final String tip;
  final bool close;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.tip,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 46,
              height: 40,
              color: _hover ? (widget.close ? const Color(0xFFE81123) : widget.ink.withValues(alpha: 0.1)) : Colors.transparent,
              child: Icon(widget.icon, size: 16, color: _hover && widget.close ? Colors.white : widget.ink),
            ),
          ),
        ),
      );
}

/// The command bar: at rest the page's name; clicked, or Ctrl+K, a live search of the app's
/// commands and your history. A link pasted there and Enter cleans it (a uwu://fix or site link is
/// opened as one); Esc closes it.
class _CommandBar extends StatefulWidget {
  const _CommandBar({super.key, required this.ink, this.flash});
  final Color ink;
  final String? flash;

  @override
  State<_CommandBar> createState() => _CommandBarState();
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
      return Positioned(
        width: 520,
        child: CompositedTransformFollower(
          link: _link,
          offset: const Offset(0, 36),
          showWhenUnlinked: false,
          child: Material(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            color: fx.uwu ? Color.alphaBlend(fx.surfaceStrong, Theme.of(context).scaffoldBackgroundColor) : Theme.of(context).colorScheme.surfaceContainerHigh,
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
            builder: (context, page, _) => TextField(
              controller: _field,
              focusNode: _focus,
              onSubmitted: _run,
              style: TextStyle(color: widget.ink, fontSize: 13.5),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: widget.ink.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                prefixIcon: Icon(Icons.search, size: 16, color: widget.ink.withValues(alpha: 0.7)),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                hintText: widget.flash ?? '${_titles[page] ?? 'uwuFix'}  ·  Ctrl+K to search, or paste a link',
                hintStyle: TextStyle(color: widget.ink.withValues(alpha: widget.flash == null ? 0.65 : 1), fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: widget.ink.withValues(alpha: 0.4))),
              ),
            ),
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

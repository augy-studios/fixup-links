// Fix a link widgets on the desktop (docs/desktop-features-spec.md §8, adapted: uwuFix has no live
// item, so its widget is the Android home screen widget's "Fix a link" bar): a small frameless
// window, each its own engine (desktop_multi_window), with a box to paste a link into and a
// paste-and-fix button, the clean link under it with Copy, and its own buttons: pin on top of
// other windows, and remove (×).
//
// Added from the tray's menu (Add a Fix a link widget) or the command bar. Moved by dragging its
// top, resized from any edge down to 200 x 110 (default 320 x 170). The links it cleans go into
// the history, through the main window. Clicking the clean link opens it in the main window.
// Widgets don't show in the taskbar. Each one's pin and place are kept (settings: widgets) and
// every widget reopens where it was when the app starts; × forgets it, quitting keeps them all.
import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../api/resolve.dart';
import '../app/links.dart';
import '../data/history.dart';
import '../data/linkfix.dart';
import '../data/store.dart';
import '../theme/theme.dart';
import 'desktop.dart';
import 'settings.dart';

const _defaultSize = Size(320, 170);

List<Map<String, dynamic>> _kept() => [for (final w in (DeskSettings.get('widgets') as List?) ?? const []) if (w is Map) Map<String, dynamic>.from(w)];

void _keep(Map<String, dynamic> widget) {
  final all = _kept().where((w) => w['id'] != widget['id']).toList()..add(widget);
  DeskSettings.set('widgets', all);
}

void _forget(String id) => DeskSettings.set('widgets', _kept().where((w) => w['id'] != id).toList());

bool _handling = false;

/// The main window's side: what widgets ask of it.
void _listen() {
  if (_handling) return;
  _handling = true;
  DesktopMultiWindow.setMethodHandler((call, from) async {
    final a = call.arguments is Map ? Map<String, dynamic>.from(call.arguments as Map) : <String, dynamic>{};
    switch (call.method) {
      case 'record':
        final e = History.add('${a['original']}', '${a['cleaned']}', '${a['platform']}');
        fetchMetadata(e.cleaned).then((m) {
          if (m?.title != null) History.update(e.id, title: m!.title);
        });
      case 'open':
        await Desktop.show();
        Links.open('${a['url']}');
      case 'removed':
        _forget('${a['id']}');
    }
    return null;
  });
}

Future<void> openWidgetWindow([Map<String, dynamic>? kept]) async {
  _listen();
  final w = kept ?? {'id': 'w${DateTime.now().millisecondsSinceEpoch}', 'onTop': true};
  if (kept == null) _keep(w);
  final c = await DesktopMultiWindow.createWindow(jsonEncode({'kind': 'widget', ...w}));
  final b = w['bounds'];
  if (b is Map) {
    await c.setFrame(Rect.fromLTWH((b['x'] as num).toDouble(), (b['y'] as num).toDouble(), (b['width'] as num).toDouble(), (b['height'] as num).toDouble()));
  } else {
    await c.setFrame(Offset.zero & _defaultSize);
    await c.center();
  }
  await c.setTitle('Fix a link');
  await c.show();
}

/// At start: every widget that was open when the app last ran.
Future<void> reopenWidgetWindows() async {
  for (final w in _kept()) {
    try {
      await openWidgetWindow(w);
    } catch (_) {}
  }
}

/// A widget's own window: its engine starts here.
Future<void> runWidgetWindow(int windowId, Map<String, dynamic> args) async {
  await Store.open();
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  await windowManager.setSkipTaskbar(true);
  await windowManager.setMinimumSize(const Size(200, 110));
  await windowManager.setAlwaysOnTop(args['onTop'] != false);
  runApp(_WidgetApp(windowId: windowId, args: args));
}

class _WidgetApp extends StatefulWidget {
  const _WidgetApp({required this.windowId, required this.args});
  final int windowId;
  final Map<String, dynamic> args;

  @override
  State<_WidgetApp> createState() => _WidgetAppState();
}

class _WidgetAppState extends State<_WidgetApp> with WindowListener {
  final _field = TextEditingController();
  late bool _onTop = widget.args['onTop'] != false;
  String? _cleaned;
  String? _error;
  Timer? _save;

  String get _id => '${widget.args['id']}';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _kept() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 600), () async {
      final b = await windowManager.getBounds();
      _keep({'id': _id, 'onTop': _onTop, 'bounds': {'x': b.left, 'y': b.top, 'width': b.width, 'height': b.height}});
    });
  }

  @override
  void onWindowMoved() => _kept();
  @override
  void onWindowResized() => _kept();

  Future<void> _fix([String? text]) async {
    if (text != null) _field.text = text;
    try {
      final r = cleanUrl(extractUrlFromText(_field.text) ?? _field.text);
      setState(() {
        _cleaned = r.cleaned;
        _error = null;
      });
      await DesktopMultiWindow.invokeMethod(0, 'record', {'original': _field.text.trim(), 'cleaned': r.cleaned, 'platform': r.platform});
      await Clipboard.setData(ClipboardData(text: r.cleaned));
    } on LinkFixError catch (e) {
      setState(() {
        _cleaned = null;
        _error = e.message;
      });
    }
  }

  Future<void> _pasteFix() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isEmpty) {
      setState(() => _error = 'Nothing’s copied.');
      return;
    }
    await _fix(t);
  }

  @override
  Widget build(BuildContext context) {
    // Dark by default, with its own compact look; light when the app's set to light.
    final mode = Store.I.get(AppLook.modeKey);
    final dark = mode != 'light';
    const accent = Color(0xFFBFF5CF);
    final bg = dark ? const Color(0xFF1B221E) : const Color(0xFFF7FAF8);
    final ink = dark ? const Color(0xFFEEF2EF) : const Color(0xFF121815);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light, colorSchemeSeed: const Color(0xFF1F6B3D), useMaterial3: true, visualDensity: VisualDensity.compact),
      home: Scaffold(
        backgroundColor: bg,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 30,
            child: Stack(children: [
              const Positioned.fill(child: DragToMoveArea(child: SizedBox.expand())),
              Row(children: [
                const SizedBox(width: 10),
                Image.asset('assets/images/logo.png', width: 16, height: 16),
                const SizedBox(width: 6),
                Text('Fix a link', style: TextStyle(color: ink, fontSize: 12.5)),
                const Spacer(),
                IconButton(
                  tooltip: _onTop ? 'Unpin from the top' : 'Pin on top of other windows',
                  iconSize: 15,
                  color: ink,
                  onPressed: () async {
                    setState(() => _onTop = !_onTop);
                    await windowManager.setAlwaysOnTop(_onTop);
                    _kept();
                  },
                  icon: Icon(_onTop ? Icons.push_pin : Icons.push_pin_outlined),
                ),
                IconButton(
                  tooltip: 'Remove this widget',
                  iconSize: 15,
                  color: ink,
                  onPressed: () async {
                    await DesktopMultiWindow.invokeMethod(0, 'removed', {'id': _id});
                    await WindowController.fromWindowId(widget.windowId).close();
                  },
                  icon: const Icon(Icons.close),
                ),
              ]),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _field,
                      style: TextStyle(color: ink, fontSize: 13),
                      onSubmitted: (_) => _fix(),
                      decoration: const InputDecoration(isDense: true, hintText: 'Paste a link', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: 'Fix what’s copied',
                    style: IconButton.styleFrom(backgroundColor: accent, foregroundColor: const Color(0xFF121815)),
                    onPressed: _pasteFix,
                    icon: const Icon(Icons.content_paste_go, size: 18),
                  ),
                ]),
                const SizedBox(height: 8),
                if (_cleaned != null)
                  Expanded(
                    child: InkWell(
                      onTap: () => DesktopMultiWindow.invokeMethod(0, 'open', {'url': _cleaned}),
                      child: Text('Copied: $_cleaned', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: dark ? accent : const Color(0xFF1F6B3D), fontSize: 12.5)),
                    ),
                  )
                else if (_error != null)
                  Text(_error!, style: const TextStyle(color: Color(0xFFFA9696), fontSize: 12.5))
                else
                  Text('The clean link is copied, ready to paste.', style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: 12)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

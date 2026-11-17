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
import '../widgets/pointer.dart';
import 'desktop.dart';
import 'settings.dart';

const _defaultSize = Size(320, 170);

/// Every widget kept in the settings file: its id, pin and place.
List<Map<String, dynamic>> _keptWidgets() {
  final kept = <Map<String, dynamic>>[];
  final stored = DesktopSettings.get('widgets') as List?;
  if (stored == null) {
    return kept;
  }
  for (final storedWidget in stored) {
    if (storedWidget is Map) {
      kept.add(Map<String, dynamic>.from(storedWidget));
    }
  }
  return kept;
}

/// Every kept widget but the one with [id].
List<Map<String, dynamic>> _keptWidgetsExcept(Object? id) {
  final others = <Map<String, dynamic>>[];
  for (final keptWidget in _keptWidgets()) {
    if (keptWidget['id'] != id) {
      others.add(keptWidget);
    }
  }
  return others;
}

void _keep(Map<String, dynamic> widget) {
  final all = _keptWidgetsExcept(widget['id']);
  all.add(widget);
  DesktopSettings.set('widgets', all);
}

void _forget(String id) {
  DesktopSettings.set('widgets', _keptWidgetsExcept(id));
}

bool _handling = false;

/// The main window's side: what widgets ask of it.
void _listen() {
  if (_handling) {
    return;
  }
  _handling = true;
  DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
    Map<String, dynamic> arguments;
    if (call.arguments is Map) {
      arguments = Map<String, dynamic>.from(call.arguments as Map);
    } else {
      arguments = <String, dynamic>{};
    }
    switch (call.method) {
      case 'record':
        final entry = History.add('${arguments['original']}', '${arguments['cleaned']}', '${arguments['platform']}');
        fetchMetadata(entry.cleaned).then((metadata) {
          if (metadata?.title != null) {
            History.update(entry.id, title: metadata!.title);
          }
        });
      case 'open':
        await Desktop.show();
        Links.open('${arguments['url']}');
      case 'removed':
        _forget('${arguments['id']}');
    }
    return null;
  });
}

/// Opens a widget's window: one that was [kept], where it was, or a new one, kept from now on.
Future<void> openWidgetWindow([Map<String, dynamic>? kept]) async {
  _listen();
  Map<String, dynamic> widget;
  if (kept != null) {
    widget = kept;
  } else {
    widget = {'id': 'w${DateTime.now().millisecondsSinceEpoch}', 'onTop': true};
    _keep(widget);
  }
  final controller = await DesktopMultiWindow.createWindow(jsonEncode({'kind': 'widget', ...widget}));
  final bounds = widget['bounds'];
  if (bounds is Map) {
    await controller.setFrame(Rect.fromLTWH((bounds['x'] as num).toDouble(), (bounds['y'] as num).toDouble(), (bounds['width'] as num).toDouble(), (bounds['height'] as num).toDouble()));
  } else {
    await controller.setFrame(Offset.zero & _defaultSize);
    await controller.center();
  }
  await controller.setTitle('Fix a link');
  await controller.show();
}

/// At start: every widget that was open when the app last ran.
Future<void> reopenWidgetWindows() async {
  for (final keptWidget in _keptWidgets()) {
    try {
      await openWidgetWindow(keptWidget);
    } catch (_) {}
  }
}

/// A widget's own window: its engine starts here.
Future<void> runWidgetWindow(int windowId, Map<String, dynamic> arguments) async {
  await Store.open();
  await windowManager.ensureInitialized();
  // window_manager makes its taskbar handle (Windows) only here, and setSkipTaskbar uses it
  // unchecked: without this, it crashed the app as each widget opened.
  await windowManager.waitUntilReadyToShow();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  await windowManager.setSkipTaskbar(true);
  await windowManager.setMinimumSize(const Size(200, 110));
  await windowManager.setAlwaysOnTop(arguments['onTop'] != false);
  runApp(_WidgetApp(windowId: windowId, arguments: arguments));
}

/// The widget's whole app, in its own window: a title strip with pin and remove, a box to paste a
/// link into, and the clean link under it.
class _WidgetApp extends StatefulWidget {
  const _WidgetApp({required this.windowId, required this.arguments});
  final int windowId;
  final Map<String, dynamic> arguments;

  @override
  State<_WidgetApp> createState() {
    return _WidgetAppState();
  }
}

class _WidgetAppState extends State<_WidgetApp> with WindowListener {
  final _field = TextEditingController();
  late bool _onTop = widget.arguments['onTop'] != false;
  String? _cleaned;
  String? _error;
  Timer? _saveTimer;

  String get _id {
    return '${widget.arguments['id']}';
  }

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

  /// Keeps this widget's pin and place, a moment after it last moved.
  void _keepPlace() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () async {
      final bounds = await windowManager.getBounds();
      _keep({'id': _id, 'onTop': _onTop, 'bounds': {'x': bounds.left, 'y': bounds.top, 'width': bounds.width, 'height': bounds.height}});
    });
  }

  @override
  void onWindowMoved() {
    _keepPlace();
  }

  @override
  void onWindowResized() {
    _keepPlace();
  }

  /// Cleans the link in the box (or [text], put in it first), records it in the main window's
  /// history and copies it; or says why it couldn't.
  Future<void> _fix([String? text]) async {
    if (text != null) {
      _field.text = text;
    }
    try {
      String linkText;
      final foundUrl = extractUrlFromText(_field.text);
      if (foundUrl != null) {
        linkText = foundUrl;
      } else {
        linkText = _field.text;
      }
      final result = cleanUrl(linkText);
      setState(() {
        _cleaned = result.cleaned;
        _error = null;
      });
      await DesktopMultiWindow.invokeMethod(0, 'record', {'original': _field.text.trim(), 'cleaned': result.cleaned, 'platform': result.platform});
      await Clipboard.setData(ClipboardData(text: result.cleaned));
    } on LinkFixError catch (error) {
      setState(() {
        _cleaned = null;
        _error = error.message;
      });
    }
  }

  Future<void> _pasteFix() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    String copied;
    final copiedText = data?.text;
    if (copiedText != null) {
      copied = copiedText.trim();
    } else {
      copied = '';
    }
    if (copied.isEmpty) {
      setState(() {
        _error = 'Nothing’s copied.';
      });
      return;
    }
    await _fix(copied);
  }

  /// Under the box: the clean link, the error, or what the widget does.
  Widget _status(bool dark, Color accent, Color ink) {
    if (_cleaned != null) {
      Color linkColor;
      if (dark) {
        linkColor = accent;
      } else {
        linkColor = const Color(0xFF1F6B3D);
      }
      return Expanded(
        child: InkWell(
          onTap: () {
            DesktopMultiWindow.invokeMethod(0, 'open', {'url': _cleaned});
          },
          child: Text('Copied: $_cleaned', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: linkColor, fontSize: 12.5)),
        ),
      );
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: Color(0xFFFA9696), fontSize: 12.5));
    }
    return Text('The clean link is copied, ready to paste.', style: TextStyle(color: ink.withValues(alpha: 0.6), fontSize: 12));
  }

  @override
  Widget build(BuildContext context) {
    // Dark by default, with its own compact look; light when the app's set to light.
    final mode = Store.I.get(AppLook.modeKey);
    final dark = mode != 'light';
    const accent = Color(0xFFBFF5CF);
    Color background;
    Color ink;
    Brightness brightness;
    if (dark) {
      background = const Color(0xFF1B221E);
      ink = const Color(0xFFEEF2EF);
      brightness = Brightness.dark;
    } else {
      background = const Color(0xFFF7FAF8);
      ink = const Color(0xFF121815);
      brightness = Brightness.light;
    }
    String pinTooltip;
    IconData pinIcon;
    if (_onTop) {
      pinTooltip = 'Unpin from the top';
      pinIcon = Icons.push_pin;
    } else {
      pinTooltip = 'Pin on top of other windows';
      pinIcon = Icons.push_pin_outlined;
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return PointerOverButtons(child: child!);
      },
      theme: ThemeData(brightness: brightness, colorSchemeSeed: const Color(0xFF1F6B3D), useMaterial3: true, visualDensity: VisualDensity.compact),
      home: Scaffold(
        backgroundColor: background,
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
                  tooltip: pinTooltip,
                  iconSize: 15,
                  color: ink,
                  onPressed: () async {
                    setState(() {
                      _onTop = !_onTop;
                    });
                    await windowManager.setAlwaysOnTop(_onTop);
                    _keepPlace();
                  },
                  icon: Icon(pinIcon),
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
                      onSubmitted: (_) {
                        _fix();
                      },
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
                _status(dark, accent, ink),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

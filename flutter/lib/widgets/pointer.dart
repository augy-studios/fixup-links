// The pointing hand over buttons on the desktop, as on the web. Off the web Flutter keeps the
// arrow over its buttons (WidgetStateMouseCursor.adaptiveClickable), and some of them take no
// cursor of their own at all: NavigationRail's and NavigationBar's destinations among them.
//
// So rather than setting it on each button, this lies over the whole app and looks at what's under
// the mouse as it moves (and after each frame, for a page that changes under a still mouse). Where
// the cursor that would show is the plain arrow and what's there can be tapped (a tap in its
// semantics, as every enabled button, InkWell, switch, check box and chip has), it shows the
// pointing hand instead. Anything with a cursor of its own (text fields, the window buttons) keeps
// it, and anything disabled keeps the arrow.
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class PointerOverButtons extends StatefulWidget {
  const PointerOverButtons({super.key, required this.child});
  final Widget child;

  /// The cursor for what's under the mouse, from the hit test there: the hand where the cursor
  /// that would win is the arrow over something tappable, otherwise left to what's there.
  static MouseCursor cursorFor(HitTestResult result) {
    var tappable = false;
    // Deepest first, as the mouse tracker reads them: the first cursor that isn't deferred wins.
    for (final entry in result.path) {
      final target = entry.target;
      if (target is SemanticsAnnotationsMixin && target.properties.onTap != null) tappable = true;
      if (target is RenderSemanticsGestureHandler && target.onTap != null) tappable = true;
      if (target is MouseTrackerAnnotation) {
        final cursor = (target as MouseTrackerAnnotation).cursor;
        if (cursor == MouseCursor.defer) continue;
        return tappable && cursor == SystemMouseCursors.basic ? SystemMouseCursors.click : MouseCursor.defer;
      }
    }
    return MouseCursor.defer;
  }

  @override
  State<PointerOverButtons> createState() => _PointerOverButtonsState();
}

class _PointerOverButtonsState extends State<PointerOverButtons> {
  final _app = GlobalKey();
  MouseCursor _cursor = MouseCursor.defer;
  Offset? _at; // where the mouse is; null while it's outside the window
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPersistentFrameCallback(_frame);
  }

  void _frame(Duration _) {
    if (!mounted || _at == null || _queued) return;
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) _look();
    });
  }

  void _look() {
    final at = _at;
    final box = _app.currentContext?.findRenderObject();
    var cursor = MouseCursor.defer;
    if (at != null && box is RenderBox && box.attached && box.hasSize) {
      final result = BoxHitTestResult();
      box.hitTest(result, position: box.globalToLocal(at));
      cursor = PointerOverButtons.cursorFor(result);
    }
    if (cursor != _cursor) setState(() => _cursor = cursor);
  }

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: [
          KeyedSubtree(key: _app, child: widget.child),
          // Over the app, so its cursor comes first, but letting the mouse through to it.
          Positioned.fill(
            child: MouseRegion(
              opaque: false,
              hitTestBehavior: HitTestBehavior.translucent,
              cursor: _cursor,
              onHover: (e) {
                _at = e.position;
                _look();
              },
              onExit: (_) {
                _at = null;
                _look();
              },
            ),
          ),
        ],
      );
}

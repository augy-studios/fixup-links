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

/// Lies over the whole app and shows the pointing hand wherever the mouse is over something that
/// can be tapped and would otherwise show the plain arrow.
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
      if (target is SemanticsAnnotationsMixin && target.properties.onTap != null) {
        tappable = true;
      }
      if (target is RenderSemanticsGestureHandler && target.onTap != null) {
        tappable = true;
      }
      if (target is MouseTrackerAnnotation) {
        final cursor = (target as MouseTrackerAnnotation).cursor;
        if (cursor == MouseCursor.defer) {
          continue;
        }
        if (tappable && cursor == SystemMouseCursors.basic) {
          return SystemMouseCursors.click;
        } else {
          return MouseCursor.defer;
        }
      }
    }
    return MouseCursor.defer;
  }

  @override
  State<PointerOverButtons> createState() {
    return _PointerOverButtonsState();
  }
}

class _PointerOverButtonsState extends State<PointerOverButtons> {
  final _appKey = GlobalKey();
  MouseCursor _cursor = MouseCursor.defer;
  Offset? _mousePosition; // where the mouse is; null while it's outside the window
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  /// After each frame, looks again at what's under a still mouse, in case the page changed.
  void _onFrame(Duration _) {
    if (!mounted || _mousePosition == null || _queued) {
      return;
    }
    _queued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (mounted) {
        _lookUnderMouse();
      }
    });
  }

  /// Hit-tests the app where the mouse is and updates the cursor to show.
  void _lookUnderMouse() {
    final mousePosition = _mousePosition;
    final box = _appKey.currentContext?.findRenderObject();
    var cursor = MouseCursor.defer;
    if (mousePosition != null && box is RenderBox && box.attached && box.hasSize) {
      final result = BoxHitTestResult();
      box.hitTest(result, position: box.globalToLocal(mousePosition));
      cursor = PointerOverButtons.cursorFor(result);
    }
    if (cursor != _cursor) {
      setState(() {
        _cursor = cursor;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.passthrough,
      children: [
        KeyedSubtree(key: _appKey, child: widget.child),
        // Over the app, so its cursor comes first, but letting the mouse through to it.
        Positioned.fill(
          child: MouseRegion(
            opaque: false,
            hitTestBehavior: HitTestBehavior.translucent,
            cursor: _cursor,
            onHover: (event) {
              _mousePosition = event.position;
              _lookUnderMouse();
            },
            onExit: (_) {
              _mousePosition = null;
              _lookUnderMouse();
            },
          ),
        ),
      ],
    );
  }
}

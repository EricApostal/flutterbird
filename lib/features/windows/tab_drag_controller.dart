import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/windows/window_system.dart';

/// What a mounted tab strip says about itself, in its window's coordinates.
class TabStripReport {
  const TabStripReport({
    required this.bounds,
    required this.tabsOrigin,
    required this.axis,
    required this.slotExtentFor,
    required this.scrollOffset,
  });

  /// See [TabStripGeometry], which this becomes once placed on screen.
  final Rect bounds;
  final Offset tabsOrigin;
  final Axis axis;
  final double Function(int tabCount) slotExtentFor;
  final double scrollOffset;
}

/// Answers null while the strip is not on show.
typedef TabStripReporter = TabStripReport? Function();

/// The tab drag in progress, between the strips of all windows.
///
/// What a drag does is [TabDrag]'s business. This gives it the app's windows
/// to work on and tells it where the mouse is.
///
/// Where the system can say where the mouse is, it is asked, many times a
/// second, rather than waiting for pointer events: a drag crosses from window
/// to window, and the widget it started in may be gone from the window it
/// started in. Elsewhere the one window's pointer events are enough.
class TabDragController extends ChangeNotifier implements TabDragHost {
  TabDragController(this._ref);

  static const Duration _pollInterval = Duration(milliseconds: 8);

  /// How many polls go by before a mouse that has not moved is looked at again.
  /// Things change under a still mouse: a new window's strip gets laid out.
  static const int _stillPolls = 6;

  final Ref _ref;
  final Map<int, List<TabStripReporter>> _strips = {};

  TabDrag? _drag;
  Timer? _poll;
  int _polls = 0;
  ScreenPoint? _polledAt;
  (int?, int?, double?)? _shown;

  WindowSystem get _windows => _ref.read(windowSystemProvider);

  bool get isDragging => _drag != null;

  int? get draggedTabId => _drag?.tabId;

  /// Where along [windowId]'s strip to draw the dragged tab, or null when it
  /// is not being slid along that strip.
  double? leadingIn(int windowId) => _drag?.leadingIn(windowId);

  /// Adds a strip of [windowId]. Returns what removes it.
  VoidCallback registerStrip(int windowId, TabStripReporter report) {
    final reporters = _strips.putIfAbsent(windowId, () => []);
    reporters.add(report);
    return () {
      reporters.remove(report);
      if (reporters.isEmpty && identical(_strips[windowId], reporters)) {
        _strips.remove(windowId);
      }
    };
  }

  /// Starts dragging a tab of [windowId]. The positions are in the window's
  /// coordinates: where the button went [down], where the [pointer] is now and
  /// where the tab's top left corner is.
  void start({
    required int windowId,
    required int tabId,
    required Offset down,
    required Offset pointer,
    required Offset tabTopLeft,
  }) {
    if (_drag != null) return;

    final grab = down - tabTopLeft;
    final mouse = _windows.cursorPosition();
    final drag = TabDrag.begin(
      this,
      tabId: tabId,
      cursor: mouse ?? _onScreen(windowId, pointer),
      grab: ScreenPoint(grab.dx, grab.dy),
    );
    if (drag == null) return;

    _drag = drag;
    _polledAt = null;
    HardwareKeyboard.instance.addHandler(_onKey);
    if (mouse != null) {
      _poll = Timer.periodic(_pollInterval, (_) => _onPoll());
    }
    drag.update(drag.cursor);
    _changed();
  }

  /// A pointer event of the window the drag started in.
  void pointerMoved(int windowId, Offset pointer) {
    final drag = _drag;
    if (drag == null || _poll != null) return;
    drag.update(_onScreen(windowId, pointer));
    _changed();
  }

  /// The pointer going up, as the window the drag started in heard it.
  void pointerReleased() {
    if (_poll == null) _end(cancel: false);
  }

  ScreenPoint _onScreen(int windowId, Offset inWindow) =>
      _windows.contentOriginOf(windowId) +
      ScreenPoint(inWindow.dx, inWindow.dy);

  void _onPoll() {
    final drag = _drag;
    if (drag == null) return;
    if (!_windows.primaryButtonDown()) {
      _end(cancel: false);
      return;
    }

    final mouse = _windows.cursorPosition()!;
    _polls++;
    if (mouse == _polledAt && _polls % _stillPolls != 0) return;
    _polledAt = mouse;
    drag.update(mouse);
    _changed();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    _end(cancel: true);
    return true;
  }

  void _changed() {
    final drag = _drag;
    if (drag == null) return;
    if (drag.isOver) {
      _end(cancel: false);
      return;
    }
    final windowId = drag.windowId;
    final shown = (
      drag.tabId,
      windowId,
      windowId == null ? null : drag.leadingIn(windowId),
    );
    if (shown == _shown) return;
    _shown = shown;
    notifyListeners();
  }

  void _end({required bool cancel}) {
    final drag = _drag;
    if (drag == null) return;

    _poll?.cancel();
    _poll = null;
    HardwareKeyboard.instance.removeHandler(_onKey);
    // Cleared first, so that strips redrawn by what finishing does already see
    // a tab that is no longer being dragged, and let it slide into its slot.
    _drag = null;
    _shown = null;
    cancel ? drag.cancel() : drag.finish();
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_drag != null) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // ------------------------------------------------------------ TabDragHost

  @override
  BrowserSession get session => _ref.read(browserSessionProvider);

  @override
  void commit(BrowserSession next) =>
      _ref.read(browserSessionProvider.notifier).commit(next);

  @override
  TabStripGeometry? stripOf(int windowId) {
    for (final reporter in _strips[windowId] ?? const <TabStripReporter>[]) {
      final report = reporter();
      if (report == null) continue;

      final origin = _windows.contentOriginOf(windowId);
      return TabStripGeometry(
        windowId: windowId,
        axis: report.axis == Axis.horizontal
            ? TabStripAxis.horizontal
            : TabStripAxis.vertical,
        bounds: ScreenRect(
          origin.x + report.bounds.left,
          origin.y + report.bounds.top,
          report.bounds.width,
          report.bounds.height,
        ),
        tabsOrigin:
            origin + ScreenPoint(report.tabsOrigin.dx, report.tabsOrigin.dy),
        slotExtentFor: report.slotExtentFor,
        scrollOffset: report.scrollOffset,
      );
    }
    return null;
  }

  @override
  int? windowAt(ScreenPoint point, {required Set<int> ignoring}) =>
      _windows.windowAt(point, ignoring);

  @override
  bool canTearOff(int windowId) =>
      _windows.supportsMultipleWindows && !_windows.isFullscreen(windowId);

  @override
  ScreenRect? windowFrame(int windowId) => _windows.frameOf(windowId);

  @override
  ScreenRect visibleScreenAt(ScreenPoint point) =>
      _windows.visibleScreenAt(point);

  @override
  void prepareWindow(int windowId, ScreenRect frame) =>
      _windows.prepareWindow(windowId, frame);

  @override
  void moveWindow(int windowId, ScreenPoint topLeft) =>
      _windows.moveWindow(windowId, topLeft);

  @override
  void setWindowParked(int windowId, bool parked) =>
      _windows.setParked(windowId, parked);

  @override
  void raiseWindow(int windowId) => _windows.raise(windowId);
}

final tabDragControllerProvider = Provider<TabDragController>((ref) {
  final controller = TabDragController(ref);
  ref.onDispose(controller.dispose);
  return controller;
});

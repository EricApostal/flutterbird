/// Dragging a tab: sliding it along its strip, pulling it out into a window of
/// its own, and docking it into the strip of any other window, all in one
/// press.
///
/// What a drag does is decided here, from where the mouse is and what the
/// windows are like. Everything that touches a real window goes through
/// [TabDragHost], so all of it can be run against made-up windows.
library;

import 'dart:math' as math;

import 'package:bird_window/bird_window.dart';

import 'browser_session.dart';
import 'window_placement.dart';

enum TabStripAxis { horizontal, vertical }

/// Where a window's tab strip is on screen, and how it lays tabs out.
final class TabStripGeometry {
  const TabStripGeometry({
    required this.windowId,
    required this.bounds,
    required this.tabsOrigin,
    required this.slotExtentFor,
    this.axis = TabStripAxis.horizontal,
    this.scrollOffset = 0,
  });

  final int windowId;
  final TabStripAxis axis;

  /// The whole strip, including the room after the last tab: a tab let go
  /// anywhere in it docks.
  final ScreenRect bounds;

  /// The top left corner of the first tab's slot when nothing is scrolled.
  final ScreenPoint tabsOrigin;

  /// How far along the strip each tab takes up when it holds [tabCount] tabs.
  final double Function(int tabCount) slotExtentFor;

  /// How far the tabs are scrolled.
  final double scrollOffset;

  double _along(ScreenPoint point) =>
      axis == TabStripAxis.horizontal ? point.x : point.y;

  /// Where the dragged tab's leading edge is, measured from the first slot, if
  /// the mouse is at [cursor] and holds the tab [grab] from its top left.
  double _rawLeading(ScreenPoint cursor, ScreenPoint grab, int tabCount) {
    // A tab can be narrower in this strip than where it was picked up.
    final held = _along(grab).clamp(0.0, slotExtentFor(tabCount));
    return _along(cursor) - held - _along(tabsOrigin) + scrollOffset;
  }

  /// Where to draw the dragged tab: under the mouse, but never off either end
  /// of the row of tabs.
  double leadingFor(ScreenPoint cursor, ScreenPoint grab, int tabCount) {
    final last = math.max(0, tabCount - 1) * slotExtentFor(tabCount);
    return _rawLeading(cursor, grab, tabCount).clamp(0.0, last);
  }

  /// The slot the dragged tab belongs in: the one it is more than half over.
  int indexFor(ScreenPoint cursor, ScreenPoint grab, int tabCount) {
    if (tabCount <= 1) return 0;
    final slot = slotExtentFor(tabCount);
    if (slot <= 0) return 0;
    return ((_rawLeading(cursor, grab, tabCount) + slot / 2) / slot)
        .floor()
        .clamp(0, tabCount - 1);
  }
}

/// What a drag needs from the app.
abstract interface class TabDragHost {
  BrowserSession get session;

  /// Makes [next] the session.
  void commit(BrowserSession next);

  /// The tab strip of a window, or null if it shows none right now, which is
  /// also the case for a moment after the window is made.
  TabStripGeometry? stripOf(int windowId);

  /// The frontmost of the app's windows at [point], leaving out [ignoring].
  /// Null if there is none, or another app's window is in front there.
  int? windowAt(ScreenPoint point, {required Set<int> ignoring});

  /// Whether a tab can be pulled out of a window into one of its own. Not on a
  /// platform with one window, and not out of a full screen window.
  bool canTearOff(int windowId);

  ScreenRect? windowFrame(int windowId);

  /// The usable area of the screen at [point].
  ScreenRect visibleScreenAt(ScreenPoint point);

  /// Called before a window is first committed to the session, to say where it
  /// should appear.
  void prepareWindow(int windowId, ScreenRect frame);

  void moveWindow(int windowId, ScreenPoint topLeft);

  /// Hides a window while keeping it alive, or shows it again.
  void setWindowParked(int windowId, bool parked);

  void raiseWindow(int windowId);
}

/// One drag of one tab, from the press that started it until it is let go.
final class TabDrag {
  TabDrag._(
    this._host, {
    required this.tabId,
    required this.grab,
    required this.originWindowId,
    required int originIndex,
    required ScreenRect? originFrame,
    required ScreenPoint anchor,
    required ScreenPoint cursor,
  }) : _originIndex = originIndex,
       _originFrame = originFrame,
       _anchor = anchor,
       _cursor = cursor;

  /// How far outside a strip a tab can be and still dock into it.
  static const double attachSlop = 4;

  /// How far outside its strip a tab has to be pulled to come off. Larger than
  /// [attachSlop], so that a tab at the edge does not flicker in and out.
  static const double detachSlop = 28;

  /// Where the first tab is in a window whose strip is not known.
  static const ScreenPoint _fallbackStripInset = ScreenPoint(118, 4);

  final TabDragHost _host;
  final int tabId;

  /// Where the mouse holds the tab, from the tab's top left corner.
  final ScreenPoint grab;

  /// The window the tab was in when the drag started.
  final int originWindowId;
  final int _originIndex;
  final ScreenRect? _originFrame;

  /// Where the mouse is in a window being carried along, from its top left, so
  /// that the tab stays under the mouse.
  final ScreenPoint _anchor;

  ScreenPoint _cursor;
  bool _floating = false;
  bool _over = false;

  /// The window that is the tab's own while it is out of every strip. It is
  /// kept, parked and empty, while the tab is docked elsewhere, and used again
  /// if the tab is pulled out again, so a drag makes one window at most.
  int? _floatingId;
  bool _floatingParked = false;

  /// Whether the drag is over, and [update] does nothing more.
  bool get isOver => _over;

  /// Whether the tab is out of every strip, in a window following the mouse.
  bool get isFloating => _floating;

  ScreenPoint get cursor => _cursor;

  /// The window the tab is in now.
  int? get windowId => _host.session.windowOfTab(tabId)?.id;

  /// Starts dragging [tabId], or returns null for a tab that cannot be dragged.
  ///
  /// A tab that is alone in its window has nothing to slide along, so the
  /// window comes with it at once.
  static TabDrag? begin(
    TabDragHost host, {
    required int tabId,
    required ScreenPoint cursor,
    required ScreenPoint grab,
  }) {
    final source = host.session.windowOfTab(tabId);
    if (source == null || source.isPopup) return null;

    final frame = host.windowFrame(source.id);
    final strip = host.stripOf(source.id);
    final inset = (frame != null && strip != null)
        ? strip.tabsOrigin - frame.topLeft
        : _fallbackStripInset;
    final alone = source.tabIds.length == 1;

    final drag = TabDrag._(
      host,
      tabId: tabId,
      grab: grab,
      originWindowId: source.id,
      originIndex: source.tabIds.indexOf(tabId),
      originFrame: frame,
      // A window carried from the start stays where it is under the mouse.
      anchor: (alone && frame != null) ? cursor - frame.topLeft : inset + grab,
      cursor: cursor,
    );

    host.commit(host.session.activateTab(tabId));
    if (alone && host.canTearOff(source.id)) {
      drag
        .._floating = true
        .._floatingId = source.id;
    }
    return drag;
  }

  /// Where to draw the dragged tab in [windowId]'s strip, measured from the
  /// first slot, or null if it is not being slid along that strip.
  double? leadingIn(int windowId) {
    if (_over || _floating || windowId != this.windowId) return null;
    final strip = _host.stripOf(windowId);
    final window = _host.session.window(windowId);
    if (strip == null || window == null) return null;
    return strip.leadingFor(_cursor, grab, window.tabIds.length);
  }

  void update(ScreenPoint cursor) {
    if (_over) return;
    _cursor = cursor;

    // The page can close its tab in the middle of a drag.
    if (_host.session.windowOfTab(tabId) == null) {
      _end();
      return;
    }

    if (_floating) {
      _updateFloating();
    } else {
      _updateAttached();
    }
  }

  void _updateFloating() {
    final floating = _floatingId!;
    if (_host.session.window(floating) == null) {
      _floating = false;
      return;
    }
    _moveFloating();

    final target = _host.windowAt(_cursor, ignoring: {floating});
    if (target != null && _accepts(target)) _dock(target);
  }

  void _updateAttached() {
    final current = windowId!;
    final strip = _host.stripOf(current);
    // Not laid out yet: nothing can be said about where the tab is.
    if (strip == null) return;

    if (!strip.bounds.contains(_cursor)) {
      // Straight from one strip onto another that is in front of it.
      final over = _host.windowAt(
        _cursor,
        ignoring: {if (_floatingParked) _floatingId!},
      );
      if (over != null && over != current && _accepts(over)) {
        _dock(over);
        return;
      }
    }

    if (strip.bounds.inflate(detachSlop).contains(_cursor) ||
        !_host.canTearOff(current)) {
      _slide(strip);
    } else {
      _tearOff(current);
    }
  }

  bool _accepts(int windowId) {
    final window = _host.session.window(windowId);
    if (window == null || window.isPopup || window.tabIds.isEmpty) {
      return false;
    }
    final strip = _host.stripOf(windowId);
    return strip != null && strip.bounds.inflate(attachSlop).contains(_cursor);
  }

  void _slide(TabStripGeometry strip) {
    final window = _host.session.window(strip.windowId)!;
    final from = window.tabIds.indexOf(tabId);
    final to = strip.indexFor(_cursor, grab, window.tabIds.length);
    if (to != from) {
      _host.commit(_host.session.reorderTab(window.id, from, to));
    }
  }

  void _dock(int target) {
    final source = windowId!;
    final strip = _host.stripOf(target)!;
    final count = _host.session.window(target)!.tabIds.length + 1;
    final index = strip.indexFor(_cursor, grab, count);
    final leavesFloating = source == _floatingId;

    var next = _host.session;
    if (leavesFloating) next = next.holdWindow(source);
    next = next.moveTab(tabId, target, index: index).focusWindow(target);

    _floating = false;
    if (leavesFloating) {
      _host.setWindowParked(source, true);
      _floatingParked = true;
    }
    _host.commit(next);
    _host.raiseWindow(target);
  }

  void _tearOff(int current) {
    final window = _host.session.window(current)!;

    if (window.tabIds.length == 1) {
      // There is nothing else in it, so the window is what comes off.
      if (_floatingId != current) _releaseFloating();
      _floatingId = current;
      _floatingParked = false;
    } else if (_floatingId case final reused?
        when reused != current && _host.session.window(reused) != null) {
      _host.commit(
        _host.session.moveTab(tabId, reused, index: 0).focusWindow(reused),
      );
      _host.setWindowParked(reused, false);
      _floatingParked = false;
    } else {
      final from = _host.windowFrame(current);
      final screen = _host.visibleScreenAt(_cursor);
      final size = from == null
          ? WindowPlacement.defaultSize
          : WindowPlacement.tearOffSize(from, screen);
      final detached = _host.session.detachTab(tabId);
      _host.prepareWindow(
        detached.windowId,
        ScreenRect.from(_floatingOrigin(), size),
      );
      _host.commit(detached.session);
      _floatingId = detached.windowId;
      _floatingParked = false;
    }

    _floating = true;
    _moveFloating();
    _host.raiseWindow(_floatingId!);
  }

  ScreenPoint _floatingOrigin() {
    final wanted = _cursor - _anchor;
    // Not under the menu bar, where its title bar could not be reached.
    final top = _host.visibleScreenAt(_cursor).top;
    return ScreenPoint(wanted.x, math.max(wanted.y, top));
  }

  void _moveFloating() {
    _host.moveWindow(_floatingId!, _floatingOrigin());
  }

  /// Gets rid of the carried window if the tab is not in it.
  void _releaseFloating() {
    final floating = _floatingId;
    if (floating == null) return;

    _host.commit(_host.session.releaseWindow(floating));
    // A window that still has tabs stays, and has to be seen again.
    if (_floatingParked && _host.session.window(floating) != null) {
      _host.setWindowParked(floating, false);
    }
    _floatingId = null;
    _floatingParked = false;
  }

  void _end() {
    _over = true;
    _floating = false;
    _releaseFloating();
  }

  /// Lets go of the tab, leaving it where it is.
  void finish() {
    if (_over) return;
    final last = windowId;
    _end();
    if (last == null || _host.session.window(last) == null) return;
    _host.commit(_host.session.activateTab(tabId).focusWindow(last));
    _host.raiseWindow(last);
  }

  /// Puts everything back the way it was before the drag.
  void cancel() {
    if (_over) return;

    final canReturn =
        _host.session.window(originWindowId) != null &&
        _host.session.windowOfTab(tabId) != null;
    if (!canReturn) {
      finish();
      return;
    }

    final originWasCarried = _floatingId == originWindowId;
    _host.commit(
      _host.session
          .moveTab(tabId, originWindowId, index: _originIndex)
          .focusWindow(originWindowId),
    );
    if (originWasCarried) {
      if (_floatingParked) {
        _host.setWindowParked(originWindowId, false);
        _floatingParked = false;
      }
      if (_originFrame case final frame?) {
        _host.moveWindow(originWindowId, frame.topLeft);
      }
    }
    _end();
    _host.raiseWindow(originWindowId);
  }
}

import 'package:bird_session/bird_session.dart';

const ScreenRect screen = ScreenRect(0, 25, 3000, 1500);

/// Made-up windows: where they are and which is in front, laid out as the
/// horizontal tab strip lays them out.
class FakeDesktop implements TabDragHost {
  static const double stripHeight = 40;
  static const double tabsInset = 118;
  static const double trailing = 56;

  @override
  BrowserSession session = BrowserSession.empty;

  final Map<int, ScreenRect> frames = {};

  /// Front first. Negative numbers stand for other apps' windows.
  final List<int> zOrder = [];
  final Map<int, ScreenRect> foreignWindows = {};
  final Set<int> parked = {};
  final Set<int> fullScreen = {};
  final Set<int> withoutStrip = {};

  /// Every window that was ever made, and every one that was destroyed.
  final List<int> created = [];
  final List<int> destroyed = [];

  bool multiWindow = true;

  int openWindow(
    List<int> tabs,
    ScreenRect frame, {
    BrowserWindowKind kind = BrowserWindowKind.normal,
  }) {
    final opened = session.openWindow(tabIds: tabs, kind: kind);
    prepareWindow(opened.windowId, frame);
    commit(opened.session);
    return opened.windowId;
  }

  /// Another app's window, in front of everything.
  void coverWith(ScreenRect frame) {
    final number = -(foreignWindows.length + 1);
    foreignWindows[number] = frame;
    zOrder.insert(0, number);
  }

  List<int> tabsOf(int windowId) => session.window(windowId)!.tabIds;

  double slotFor(int windowId, int count) =>
      ((frames[windowId]!.width - tabsInset - trailing) / count).clamp(
        172.0,
        227.0,
      );

  /// A point in the strip of [windowId], [dx] along from the first slot.
  ScreenPoint inStrip(int windowId, double dx, [double dy = 20]) {
    final frame = frames[windowId]!;
    return ScreenPoint(frame.left + tabsInset + dx, frame.top + dy);
  }

  @override
  void commit(BrowserSession next) {
    for (final window in next.windows) {
      if (session.window(window.id) == null && !created.contains(window.id)) {
        if (!frames.containsKey(window.id)) {
          throw StateError('window ${window.id} was never given a frame');
        }
        created.add(window.id);
        zOrder.insert(0, window.id);
      }
    }
    for (final window in session.windows) {
      if (next.window(window.id) == null) {
        destroyed.add(window.id);
        frames.remove(window.id);
        zOrder.remove(window.id);
        parked.remove(window.id);
      }
    }
    session = next;
  }

  @override
  TabStripGeometry? stripOf(int windowId) {
    final frame = frames[windowId];
    final window = session.window(windowId);
    if (frame == null || window == null || window.isPopup) return null;
    if (withoutStrip.contains(windowId)) return null;
    return TabStripGeometry(
      windowId: windowId,
      bounds: ScreenRect(frame.left, frame.top, frame.width, stripHeight),
      tabsOrigin: ScreenPoint(frame.left + tabsInset, frame.top + 4),
      slotExtentFor: (count) => slotFor(windowId, count),
    );
  }

  @override
  int? windowAt(ScreenPoint point, {required Set<int> ignoring}) {
    for (final id in zOrder) {
      if (ignoring.contains(id)) continue;
      final frame = id < 0 ? foreignWindows[id]! : frames[id]!;
      if (frame.contains(point)) return id < 0 ? null : id;
    }
    return null;
  }

  @override
  bool canTearOff(int windowId) =>
      multiWindow && !fullScreen.contains(windowId);

  @override
  ScreenRect? windowFrame(int windowId) => frames[windowId];

  @override
  ScreenRect visibleScreenAt(ScreenPoint point) => screen;

  @override
  void prepareWindow(int windowId, ScreenRect frame) {
    frames[windowId] = frame;
  }

  @override
  void moveWindow(int windowId, ScreenPoint topLeft) {
    frames[windowId] = frames[windowId]!.moveTo(topLeft);
  }

  @override
  void setWindowParked(int windowId, bool value) {
    value ? parked.add(windowId) : parked.remove(windowId);
  }

  @override
  void raiseWindow(int windowId) {
    zOrder
      ..remove(windowId)
      ..insert(0, windowId);
  }
}

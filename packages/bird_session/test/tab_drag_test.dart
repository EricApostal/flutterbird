import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

import 'support/fake_desktop.dart';

/// Where in the tab every drag here holds it.
const grab = ScreenPoint(40, 16);

const left = ScreenRect(100, 100, 1000, 700);
const right = ScreenRect(1300, 300, 1000, 700);

/// Far from every strip and every window.
const nowhere = ScreenPoint(2700, 1200);

/// The mouse holding the tab in [index] of [windowId]'s strip.
ScreenPoint holding(FakeDesktop desktop, int windowId, int index) {
  final slot = desktop.slotFor(windowId, desktop.tabsOf(windowId).length);
  return desktop.inStrip(windowId, index * slot + grab.x);
}

TabDrag start(FakeDesktop desktop, int tabId) {
  final window = desktop.session.windowOfTab(tabId)!;
  return TabDrag.begin(
    desktop,
    tabId: tabId,
    cursor: holding(desktop, window.id, window.tabIds.indexOf(tabId)),
    grab: grab,
  )!;
}

void main() {
  late FakeDesktop desktop;

  setUp(() => desktop = FakeDesktop());

  group('sliding along a strip', () {
    test('reorders once the tab is more than half over a neighbour', () {
      final window = desktop.openWindow([1, 2, 3], left);
      final slot = desktop.slotFor(window, 3);
      final drag = start(desktop, 1);

      drag.update(desktop.inStrip(window, grab.x + slot * 0.4));
      expect(desktop.tabsOf(window), [1, 2, 3]);

      drag.update(desktop.inStrip(window, grab.x + slot * 0.6));
      expect(desktop.tabsOf(window), [2, 1, 3]);

      drag.update(desktop.inStrip(window, grab.x + slot * 2));
      expect(desktop.tabsOf(window), [2, 3, 1]);
      drag.finish();
      expect(desktop.tabsOf(window), [2, 3, 1]);
      expect(desktop.session.window(window)!.activeTabId, 1);
    });

    test('draws the tab under the mouse and keeps it on the row', () {
      final window = desktop.openWindow([1, 2, 3], left);
      final slot = desktop.slotFor(window, 3);
      final drag = start(desktop, 2);

      drag.update(desktop.inStrip(window, grab.x + 100));
      expect(drag.leadingIn(window), closeTo(100, 0.001));

      drag.update(desktop.inStrip(window, -60));
      expect(drag.leadingIn(window), 0);

      drag.update(desktop.inStrip(window, slot * 3 + 100));
      expect(drag.leadingIn(window), closeTo(slot * 2, 0.001));
    });

    test('a small slip off the strip does not tear the tab off', () {
      final window = desktop.openWindow([1, 2], left);
      final drag = start(desktop, 1);

      drag.update(desktop.inStrip(window, 200, FakeDesktop.stripHeight + 20));

      expect(drag.isFloating, isFalse);
      expect(desktop.created, [window]);
    });
  });

  group('tearing off', () {
    test('makes a window that keeps the tab under the mouse', () {
      final window = desktop.openWindow([1, 2, 3], left);
      final drag = start(desktop, 2);

      drag.update(nowhere);

      expect(drag.isFloating, isTrue);
      final floating = drag.windowId!;
      expect(floating, isNot(window));
      expect(desktop.tabsOf(window), [1, 3]);
      expect(desktop.session.window(window)!.activeTabId, 1);
      expect(desktop.tabsOf(floating), [2]);
      expect(desktop.frames[floating]!.size, left.size);
      // The first slot of the new window, held where the tab was held.
      expect(desktop.inStrip(floating, grab.x, 4 + grab.y), nowhere);
      expect(drag.leadingIn(floating), isNull);
    });

    test('the window follows the mouse and stays where it is dropped', () {
      desktop.openWindow([1, 2], left);
      final drag = start(desktop, 2);
      drag.update(nowhere);
      final floating = drag.windowId!;
      final before = desktop.frames[floating]!;

      drag.update(nowhere + const ScreenPoint(-300, -200));
      final after = desktop.frames[floating]!;
      expect(after.topLeft - before.topLeft, const ScreenPoint(-300, -200));

      drag.finish();
      expect(desktop.frames[floating], after);
      expect(desktop.parked, isEmpty);
      expect(desktop.session.focusedWindowId, floating);
      expect(desktop.destroyed, isEmpty);
    });

    test('the window never goes under the menu bar', () {
      desktop.openWindow([1, 2], left);
      final drag = start(desktop, 2);

      drag.update(const ScreenPoint(2700, 2));

      expect(desktop.frames[drag.windowId!]!.top, screen.top);
    });

    test('a tab alone in its window carries the window itself', () {
      final window = desktop.openWindow([1], left);
      final drag = start(desktop, 1);

      expect(drag.isFloating, isTrue);
      drag.update(holding(desktop, window, 0) + const ScreenPoint(500, 300));

      expect(desktop.created, [window]);
      expect(
        desktop.frames[window]!.topLeft,
        left.topLeft + const ScreenPoint(500, 300),
      );
      drag.finish();
      expect(desktop.destroyed, isEmpty);
    });

    test('is not possible out of a full screen window', () {
      final window = desktop.openWindow([1, 2], left);
      desktop.fullScreen.add(window);
      final drag = start(desktop, 1);

      drag.update(nowhere);

      expect(drag.isFloating, isFalse);
      expect(desktop.created, [window]);
      // It goes as far along the row as it can.
      expect(desktop.tabsOf(window), [2, 1]);
    });
  });

  group('docking', () {
    test('puts the tab in the other strip where the mouse is', () {
      final from = desktop.openWindow([1, 2], left);
      final to = desktop.openWindow([3, 4], right);
      final drag = start(desktop, 2);
      drag.update(nowhere);
      final floating = drag.windowId!;

      final slot = desktop.slotFor(to, 3);
      drag.update(desktop.inStrip(to, slot + grab.x));

      expect(drag.isFloating, isFalse);
      expect(desktop.tabsOf(to), [3, 2, 4]);
      expect(desktop.session.window(to)!.activeTabId, 2);
      expect(drag.leadingIn(to), closeTo(slot, 0.001));
      expect(desktop.zOrder.first, to);
      // The window it was in is out of sight but not gone: the tab may leave.
      expect(desktop.parked, {floating});
      expect(desktop.destroyed, isEmpty);

      drag.finish();
      expect(desktop.destroyed, [floating]);
      expect(desktop.tabsOf(from), [1]);
      expect(desktop.session.focusedWindowId, to);
    });

    test('slides along the strip it docked into', () {
      desktop.openWindow([1, 2], left);
      final to = desktop.openWindow([3, 4], right);
      final drag = start(desktop, 2);
      drag.update(nowhere);
      drag.update(desktop.inStrip(to, grab.x));
      expect(desktop.tabsOf(to), [2, 3, 4]);

      drag.update(desktop.inStrip(to, desktop.slotFor(to, 3) * 2 + grab.x));

      expect(desktop.tabsOf(to), [3, 4, 2]);
    });

    test('pulling out again uses the same window', () {
      final from = desktop.openWindow([1, 2], left);
      final to = desktop.openWindow([3], right);
      final drag = start(desktop, 2);
      drag.update(nowhere);
      final floating = drag.windowId!;

      for (var round = 0; round < 3; round++) {
        drag.update(desktop.inStrip(to, 200));
        expect(drag.windowId, to);
        expect(desktop.parked, {floating});

        drag.update(nowhere);
        expect(drag.windowId, floating);
        expect(drag.isFloating, isTrue);
        expect(desktop.parked, isEmpty);
        expect(desktop.tabsOf(to), [3]);
      }

      expect(desktop.created, [from, to, floating]);
      expect(desktop.destroyed, isEmpty);
    });

    test('works back into the window the tab came from', () {
      final from = desktop.openWindow([1, 2], left);
      final drag = start(desktop, 2);
      drag.update(nowhere);
      final floating = drag.windowId!;

      drag.update(desktop.inStrip(from, grab.x));
      drag.finish();

      expect(desktop.tabsOf(from), [2, 1]);
      expect(desktop.destroyed, [floating]);
    });

    test('a carried window docked elsewhere is closed on release', () {
      final from = desktop.openWindow([1], left);
      final to = desktop.openWindow([2], right);
      final drag = start(desktop, 1);

      drag.update(desktop.inStrip(to, 300));
      expect(desktop.parked, {from});
      expect(desktop.session.window(from), isNotNull);

      drag.finish();
      expect(desktop.destroyed, [from]);
      expect(desktop.tabsOf(to), [2, 1]);
      expect(desktop.session.windows.single.id, to);
    });

    test('goes straight from a strip to one in front of it', () {
      desktop.openWindow([1, 2], left);
      // Overlaps the bottom edge of the first strip.
      final to = desktop.openWindow([3], const ScreenRect(500, 138, 900, 600));
      final from = desktop.session.windows.first.id;
      final drag = start(desktop, 2);

      drag.update(const ScreenPoint(900, 160));

      expect(drag.windowId, to);
      expect(desktop.tabsOf(from), [1]);
    });

    test('does not happen through another app\'s window', () {
      desktop.openWindow([1, 2], left);
      final to = desktop.openWindow([3], right);
      desktop.coverWith(right);
      final drag = start(desktop, 2);
      drag.update(nowhere);

      drag.update(desktop.inStrip(to, 100));

      expect(drag.isFloating, isTrue);
      expect(desktop.tabsOf(to), [3]);
    });

    test('does not happen below a strip', () {
      desktop.openWindow([1, 2], left);
      final to = desktop.openWindow([3], right);
      final drag = start(desktop, 2);
      drag.update(nowhere);

      drag.update(desktop.inStrip(to, 100, 200));

      expect(drag.isFloating, isTrue);
    });

    test('never goes into a popup', () {
      desktop.openWindow([1, 2], left);
      final popup = desktop.openWindow(
        [3],
        right,
        kind: BrowserWindowKind.popup,
      );
      final drag = start(desktop, 2);
      drag.update(nowhere);

      drag.update(ScreenPoint(right.left + 200, right.top + 20));

      expect(drag.isFloating, isTrue);
      expect(desktop.tabsOf(popup), [3]);
    });

    test('a popup\'s tab cannot be dragged', () {
      desktop.openWindow([3], right, kind: BrowserWindowKind.popup);
      expect(
        TabDrag.begin(desktop, tabId: 3, cursor: nowhere, grab: grab),
        isNull,
      );
    });
  });

  group('cancelling', () {
    test('puts a torn off tab back where it was', () {
      final from = desktop.openWindow([1, 2, 3], left);
      final drag = start(desktop, 2);
      drag.update(nowhere);
      final floating = drag.windowId!;

      drag.cancel();

      expect(desktop.tabsOf(from), [1, 2, 3]);
      expect(desktop.session.window(from)!.activeTabId, 2);
      expect(desktop.destroyed, [floating]);
      expect(drag.isOver, isTrue);
    });

    test('brings a docked tab back and closes the spare window', () {
      final from = desktop.openWindow([1, 2], left);
      final to = desktop.openWindow([3], right);
      final drag = start(desktop, 2);
      drag.update(nowhere);
      final floating = drag.windowId!;
      drag.update(desktop.inStrip(to, 100));

      drag.cancel();

      expect(desktop.tabsOf(from), [1, 2]);
      expect(desktop.tabsOf(to), [3]);
      expect(desktop.destroyed, [floating]);
    });

    test('moves a carried window back and shows it', () {
      final from = desktop.openWindow([1], left);
      final to = desktop.openWindow([2], right);
      final drag = start(desktop, 1);
      drag.update(nowhere);
      drag.update(desktop.inStrip(to, 300));

      drag.cancel();

      expect(desktop.tabsOf(from), [1]);
      expect(desktop.frames[from], left);
      expect(desktop.parked, isEmpty);
      expect(desktop.destroyed, isEmpty);
      expect(desktop.session.window(from)!.isHeld, isFalse);
    });
  });

  group('things changing under the drag', () {
    test('a page closing its tab ends the drag and cleans up', () {
      final from = desktop.openWindow([1, 2], left);
      final to = desktop.openWindow([3], right);
      final drag = start(desktop, 2);
      drag.update(nowhere);
      final floating = drag.windowId!;
      drag.update(desktop.inStrip(to, 100));

      desktop.commit(desktop.session.removeTab(2));
      drag.update(desktop.inStrip(to, 120));

      expect(drag.isOver, isTrue);
      expect(desktop.destroyed, [floating]);
      expect(desktop.session.windows.map((w) => w.id), [from, to]);
    });

    test('a strip that is not laid out yet is waited for', () {
      final window = desktop.openWindow([1, 2], left);
      final drag = start(desktop, 1);
      desktop.withoutStrip.add(window);

      drag.update(nowhere);

      expect(drag.isFloating, isFalse);
      expect(desktop.tabsOf(window), [1, 2]);
    });

    test('nothing happens after the drag is over', () {
      final window = desktop.openWindow([1, 2], left);
      final drag = start(desktop, 1);
      drag.finish();

      drag.update(nowhere);
      drag.cancel();

      expect(desktop.tabsOf(window), [1, 2]);
      expect(drag.leadingIn(window), isNull);
    });
  });

  group('on a platform with one window', () {
    test('a tab only slides', () {
      desktop.multiWindow = false;
      final window = desktop.openWindow([1], left);
      final drag = start(desktop, 1);

      expect(drag.isFloating, isFalse);
      drag.update(nowhere);
      drag.finish();

      expect(desktop.frames[window], left);
      expect(desktop.created, [window]);
    });
  });

  group('strip geometry', () {
    TabStripGeometry vertical({double scroll = 0}) => TabStripGeometry(
      windowId: 1,
      axis: TabStripAxis.vertical,
      bounds: const ScreenRect(0, 0, 272, 700),
      tabsOrigin: const ScreenPoint(8, 44),
      slotExtentFor: (_) => 42,
      scrollOffset: scroll,
    );

    test('measures down a vertical strip', () {
      final strip = vertical();
      const cursor = ScreenPoint(500, 44 + 42 * 2 + 10);
      expect(strip.indexFor(cursor, const ScreenPoint(5, 10), 5), 2);
      expect(strip.leadingFor(cursor, const ScreenPoint(5, 10), 5), 84);
    });

    test('counts what is scrolled out of sight', () {
      final strip = vertical(scroll: 84);
      expect(
        strip.indexFor(const ScreenPoint(0, 54), const ScreenPoint(5, 10), 8),
        2,
      );
    });

    test('keeps the hold inside a narrower tab', () {
      final strip = TabStripGeometry(
        windowId: 1,
        bounds: const ScreenRect(0, 0, 1000, 40),
        tabsOrigin: ScreenPoint.zero,
        slotExtentFor: (_) => 100,
      );
      // Held 180 along a wide tab, which this strip's tabs are not.
      expect(
        strip.leadingFor(
          const ScreenPoint(300, 0),
          const ScreenPoint(180, 0),
          5,
        ),
        200,
      );
    });
  });
}

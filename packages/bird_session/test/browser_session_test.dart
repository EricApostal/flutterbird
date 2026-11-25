import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

/// What every session has to be, whatever was done to it.
void expectSound(BrowserSession session) {
  final tabs = session.allTabIds.toList();
  expect(tabs.toSet().length, tabs.length, reason: 'a tab is in two windows');
  final ids = session.windows.map((window) => window.id).toList();
  expect(session.focusOrder.toSet(), ids.toSet());
  expect(session.focusOrder.length, ids.length);
  for (final window in session.windows) {
    expect(window.id, lessThan(session.nextWindowId));
    if (window.tabIds.isEmpty) {
      expect(window.isHeld, isTrue, reason: 'empty window ${window.id}');
      expect(window.activeTabId, isNull);
    } else {
      expect(window.tabIds, contains(window.activeTabId));
    }
  }
}

void main() {
  group('tabs in one window', () {
    test('closing the active tab shows the one before it', () {
      var session = BrowserSession.single([1, 2, 3]).activateTab(2);
      session = session.removeTab(2);
      expect(session.window(1)!.activeTabId, 1);
      expect(session.window(1)!.tabIds, [1, 3]);
      expectSound(session);
    });

    test('closing the active first tab shows the one after it', () {
      final session = BrowserSession.single([1, 2, 3]).removeTab(1);
      expect(session.window(1)!.activeTabId, 2);
    });

    test('closing a background tab leaves the active one', () {
      final session = BrowserSession.single([
        1,
        2,
        3,
      ]).activateTab(3).removeTab(1);
      expect(session.window(1)!.activeTabId, 3);
    });

    test('inserting can leave the active tab alone', () {
      final session = BrowserSession.single([
        1,
        2,
      ]).insertTab(1, 3, index: 1, activate: false);
      expect(session.window(1)!.tabIds, [1, 3, 2]);
      expect(session.window(1)!.activeTabId, 1);
    });

    test('a tab already in a window is not inserted again', () {
      final session = BrowserSession.single([1]);
      expect(session.insertTab(1, 1), same(session));
    });

    test('reordering keeps the active tab', () {
      final session = BrowserSession.single([1, 2, 3]).reorderTab(1, 0, 2);
      expect(session.window(1)!.tabIds, [2, 3, 1]);
      expect(session.window(1)!.activeTabId, 1);
    });
  });

  group('windows are equals', () {
    test('closing the first window keeps the one torn out of it', () {
      var session = BrowserSession.single([1]).insertTab(1, 2);
      final detached = session.detachTab(2);
      session = detached.session.closeWindow(1);

      expect(session.windows.single.id, detached.windowId);
      expect(session.windows.single.tabIds, [2]);
      expect(session.isEmpty, isFalse);
      expectSound(session);
    });

    test('moving the last tab out of the first window removes only it', () {
      var session = BrowserSession.single([1]);
      final second = session.openWindow(tabIds: [2]);
      session = second.session.moveTab(1, second.windowId, index: 0);

      expect(session.windows.single.id, second.windowId);
      expect(session.windows.single.tabIds, [1, 2]);
      expect(session.windows.single.activeTabId, 1);
      expectSound(session);
    });

    test('the session is empty only when the last window goes', () {
      final two = BrowserSession.single([1]).openWindow(tabIds: [2]);
      final one = two.session.closeWindow(two.windowId);
      expect(one.isEmpty, isFalse);
      expect(one.removeTab(1).isEmpty, isTrue);
    });

    test('window ids are not used again', () {
      var session = BrowserSession.single([1]);
      final second = session.openWindow(tabIds: [2]);
      session = second.session.closeWindow(second.windowId);
      expect(session.openWindow(tabIds: [3]).windowId, second.windowId + 1);
    });

    test('opening a window with a tab moves it there', () {
      final opened = BrowserSession.single([1, 2]).openWindow(tabIds: [2]);
      expect(opened.session.window(1)!.tabIds, [1]);
      expect(opened.session.window(opened.windowId)!.tabIds, [2]);
      expectSound(opened.session);
    });
  });

  group('focus', () {
    test('goes back to the window focused before the one that closed', () {
      var session = BrowserSession.single([1]);
      session = session.openWindow(tabIds: [2]).session;
      session = session.openWindow(tabIds: [3]).session;
      session = session.focusWindow(1).focusWindow(3);

      expect(session.closeWindow(3).focusedWindowId, 1);
    });

    test('a window opened without focus goes to the back', () {
      final session = BrowserSession.single([
        1,
      ]).openWindow(tabIds: [2], focus: false).session;
      expect(session.focusedWindowId, 1);
      expect(session.focusedTabId, 1);
    });

    test('the last normal window is found behind a popup', () {
      final session = BrowserSession.single([
        1,
      ]).openWindow(tabIds: [2], kind: BrowserWindowKind.popup).session;
      expect(session.focusedTabId, 2);
      expect(session.lastFocused(kind: BrowserWindowKind.normal)!.id, 1);
    });
  });

  group('held windows', () {
    test('outlive their last tab until released', () {
      var session = BrowserSession.single([1]);
      final other = session.openWindow(tabIds: [2]);
      session = other.session.holdWindow(1).moveTab(1, other.windowId);

      expect(session.window(1)!.tabIds, isEmpty);
      expect(session.lastFocused()!.id, other.windowId);
      expectSound(session);

      session = session.releaseWindow(1);
      expect(session.window(1), isNull);
      expectSound(session);
    });

    test('with tabs are kept when released', () {
      final session = BrowserSession.single([1]).holdWindow(1).releaseWindow(1);
      expect(session.window(1)!.isHeld, isFalse);
    });
  });
}

import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/state/history_bitmap_cache.dart';
import 'package:flutterbird/features/browser/state/tab_preview_cache.dart';
import 'package:flutterbird/features/router/controller.dart';
import 'package:flutterbird/features/windows/window_system.dart';
import 'package:ladybird/ladybird.dart';

/// A tab that was closed, as much of it as can be brought back: where it was.
class ClosedTabRecord {
  const ClosedTabRecord({required this.url, required this.title});

  final String url;
  final String title;
}

/// Everything that opens and closes tabs and windows goes through here, so
/// that the tabs' controllers, the session that says which window each is in,
/// and the windows on screen stay in step. It has no widgets, because much of
/// what happens to tabs does not start in one: a page calling `window.open` or
/// `window.close`, or an extension.
///
/// With one window (see [WindowSystem.supportsMultipleWindows]) the tab on
/// screen is also the route the app is on, and this keeps the two together.
class BrowserShell {
  BrowserShell(this._ref);

  /// The height of what a popup window shows above its page: the title bar and
  /// the address.
  static const double popupChromeHeight =
      _titleBarHeight + popupLocationBarHeight;
  static const double popupLocationBarHeight = 36;
  static const double _titleBarHeight = 28;

  static const int _maxClosedTabs = 25;
  static final RegExp _tabRoute = RegExp(r'^/browser/tab/(\d+)');

  final Ref _ref;

  /// The tabs closed this session, most recently closed last.
  final List<ClosedTabRecord> _closedTabs = [];

  /// The tab that opened each tab that a page opened (a link that opens a new
  /// tab, `window.open`, view source). Going back from the start of such a tab
  /// closes it and returns to the one that opened it, as in a browser.
  final Map<int, int> _openerByTab = {};

  /// The window each popup was opened from, to go back to when it closes.
  final Map<int, int> _openerByPopupWindow = {};

  final Set<int> _wired = {};

  BrowserSession get session => _ref.read(browserSessionProvider);

  WindowSystem get _windows => _ref.read(windowSystemProvider);

  bool get supportsMultipleWindows => _windows.supportsMultipleWindows;

  List<LadybirdController> get _controllers =>
      _ref.read(browserTabControllerProvider);

  BrowserTabController get _tabs =>
      _ref.read(browserTabControllerProvider.notifier);

  void _commit(BrowserSession next) =>
      _ref.read(browserSessionProvider.notifier).commit(next);

  LadybirdController? controllerFor(int tabId) {
    for (final controller in _controllers) {
      if (controller.viewId == tabId) return controller;
    }
    return null;
  }

  /// Starts listening for what pages do to tabs.
  void start() {
    // A phone has nowhere to show a prompt yet, so there the engine goes on
    // refusing what pages ask for.
    if (!Platform.isAndroid && !Platform.isIOS) {
      LadybirdSiteBridge.instance.start();
    }
    _ref.listen<List<LadybirdController>>(
      browserTabControllerProvider,
      (_, _) => _wireAll(_controllers),
      fireImmediately: true,
    );
    // Views that are no tab, such as an extension's popup, can open tabs too.
    LadybirdController.fallbackNewWebViewHandler = (request) =>
        _onNewWebView(request, openerTabId: null);

    if (!supportsMultipleWindows) {
      routerController.routerDelegate.addListener(_onRoute);
      _ref.onDispose(
        () => routerController.routerDelegate.removeListener(_onRoute),
      );
    }
  }

  /// For the platforms with one window, which is the app: it stays even while
  /// it has no tabs, as when the tab switcher closes the last one.
  void keepOnlyWindow() =>
      _commit(session.holdWindow(session.windows.first.id));

  void _wireAll(List<LadybirdController> controllers) {
    final present = {for (final c in controllers) c.viewId};
    _wired.retainAll(present);
    for (final controller in controllers) {
      if (!_wired.add(controller.viewId)) continue;
      final tabId = controller.viewId;
      controller.onNewWebView = (request) =>
          _onNewWebView(request, openerTabId: tabId);
      controller.onCloseRequested = () => _onPageClosed(tabId);
    }
  }

  // ------------------------------------------------------------ one window

  void _onRoute() {
    final path = routerController.routeInformationProvider.value.uri.path;
    final match = _tabRoute.firstMatch(path);
    if (match == null) return;
    _commit(session.activateTab(int.parse(match.group(1)!)));
  }

  /// With one window, shows the route of the tab the session says is showing.
  void _route(int tabId) {
    if (supportsMultipleWindows) return;
    routerController.go('/browser/tab/$tabId');
  }

  // ------------------------------------------------------------ tabs

  void showTab(int tabId) {
    if (session.windowOfTab(tabId) == null) return;
    _commit(session.activateTab(tabId));
    _route(tabId);
  }

  /// Opens a tab in [windowId], or in the browser window used last if that is
  /// not one that takes tabs.
  LadybirdController openTab({
    int? windowId,
    String? url,
    bool activate = true,
  }) {
    var target = windowId == null ? null : session.window(windowId);
    if (target == null || target.isPopup) {
      target = supportsMultipleWindows
          ? session.lastFocused(kind: BrowserWindowKind.normal)
          : session.windows.first;
    }

    final controller = _tabs.add();
    if (url != null) controller.navigate(url);

    if (target == null) {
      _openWindowWith(controller.viewId);
    } else {
      _commit(
        session.insertTab(target.id, controller.viewId, activate: activate),
      );
      if (activate) _route(controller.viewId);
    }
    return controller;
  }

  /// Opens the tab closed last again, in a new tab of [windowId].
  bool reopenClosedTab({int? windowId}) {
    if (_closedTabs.isEmpty) return false;
    final record = _closedTabs.removeLast();
    openTab(windowId: windowId, url: record.url);
    return true;
  }

  /// The tab that opened [tabId], if both are still open.
  int? openerOf(int tabId) {
    final opener = _openerByTab[tabId];
    return opener == null || session.windowOfTab(opener) == null
        ? null
        : opener;
  }

  /// Closes a tab now. A window goes with its last tab, and the app with its
  /// last window. With [stayPut], whatever is on screen stays there, which is
  /// for a screen that is not a tab's: the tab switcher.
  void closeTab(int tabId, {bool stayPut = false}) {
    final window = session.windowOfTab(tabId);
    if (window == null) return;

    // The one window's last tab is the app.
    if (!supportsMultipleWindows && !stayPut && session.allTabIds.length == 1) {
      exit(0);
    }

    final wasActive = window.activeTabId == tabId;
    _rememberClosedTab(controllerFor(tabId));
    _commit(session.removeTab(tabId));

    final after = session.window(window.id);
    if (after == null) {
      _afterWindowClosed(window.id);
    } else if (wasActive && !stayPut) {
      if (after.activeTabId case final next?) _route(next);
    }
    _disposeTab(tabId);
  }

  void _disposeTab(int tabId) {
    _openerByTab.remove(tabId);
    _openerByTab.removeWhere((_, opener) => opener == tabId);
    _tabs.remove(tabId);
    HistoryBitmapCache.instance.evictTab(tabId);
    TabPreviewCache.instance.evict(tabId);
    BrowserWindow.forgetTab(tabId);
  }

  void _rememberClosedTab(LadybirdController? controller) {
    if (controller == null) return;
    final url = controller.urlNotifier.value;
    // A tab that never left the new-tab page has nothing to bring back.
    if (url.isEmpty || url == 'about:newtab' || url == 'about:blank') return;

    _closedTabs.add(
      ClosedTabRecord(url: url, title: controller.titleNotifier.value),
    );
    if (_closedTabs.length > _maxClosedTabs) _closedTabs.removeAt(0);
  }

  // A page closed itself, as a sign-in popup does when it is done.
  void _onPageClosed(int tabId) {
    // With one window, a page closing the only tab would close the app. Its
    // view is gone either way, so it is replaced.
    if (!supportsMultipleWindows && session.allTabIds.length == 1) openTab();
    closeTab(tabId);
  }

  // ------------------------------------------------------------ windows

  /// Opens a browser window with one new tab. With one window there is only
  /// the tab.
  int openWindow({String? url}) {
    if (!supportsMultipleWindows) {
      return session.windowOfTab(openTab(url: url).viewId)!.id;
    }
    final controller = _tabs.add();
    if (url != null) controller.navigate(url);
    return _openWindowWith(controller.viewId);
  }

  int _openWindowWith(int tabId) {
    final from = session.lastFocused(kind: BrowserWindowKind.normal);
    final frame = from == null ? null : _windows.frameOf(from.id);
    final opened = session.openWindow(tabIds: [tabId]);
    if (frame != null) {
      _windows.prepareWindow(
        opened.windowId,
        WindowPlacement.cascaded(frame, _windows.visibleScreenAt(frame.center)),
      );
    }
    _commit(opened.session);
    _route(tabId);
    return opened.windowId;
  }

  /// Opens a popup window: [url] in a window with no tab strip.
  int openPopupWindow({String? url, int? width, int? height}) {
    if (!supportsMultipleWindows) return openWindow(url: url);
    final controller = _tabs.add();
    if (url != null) controller.navigate(url);
    return _showAsPopup(
      controller.viewId,
      openerWindowId: session.focusedWindowId,
      width: width,
      height: height,
    );
  }

  int _showAsPopup(
    int tabId, {
    required int? openerWindowId,
    int? width,
    int? height,
  }) {
    final openerFrame = openerWindowId == null
        ? null
        : _windows.frameOf(openerWindowId);
    final screen = _windows.visibleScreenAt(
      openerFrame?.center ?? ScreenPoint.zero,
    );

    final opened = session.openWindow(
      kind: BrowserWindowKind.popup,
      tabIds: [tabId],
    );
    _windows.prepareWindow(
      opened.windowId,
      WindowPlacement.popup(
        opener: openerFrame ?? screen,
        screen: screen,
        chromeHeight: popupChromeHeight,
        width: width,
        height: height,
      ),
    );
    if (openerWindowId != null) {
      _openerByPopupWindow[opened.windowId] = openerWindowId;
    }
    _commit(opened.session);
    return opened.windowId;
  }

  /// Closes one window and its tabs, and nothing else. Other windows carry on,
  /// whichever of them was opened first.
  void closeWindow(int windowId) {
    final window = session.window(windowId);
    if (window == null) return;
    if (!supportsMultipleWindows) exit(0);

    for (final tabId in window.tabIds) {
      _rememberClosedTab(controllerFor(tabId));
    }
    _commit(session.closeWindow(windowId));
    _afterWindowClosed(windowId);
    for (final tabId in window.tabIds) {
      _disposeTab(tabId);
    }
  }

  void _afterWindowClosed(int windowId) {
    // A popup gives the keyboard back to the window that opened it, which is
    // where a sign-in carries on.
    final opener = _openerByPopupWindow.remove(windowId);
    if (opener != null && session.window(opener) != null) {
      _commit(session.focusWindow(opener));
      _windows.raise(opener);
    }
    _openerByPopupWindow.removeWhere((_, value) => value == windowId);
  }

  // ------------------------------------------------------------ views from pages

  void _onNewWebView(
    LadybirdNewWebViewRequest request, {
    required int? openerTabId,
  }) {
    final tabId = request.viewId;
    if (session.windowOfTab(tabId) != null) return;

    final opener = openerTabId == null
        ? null
        : session.windowOfTab(openerTabId);
    if (openerTabId != null && openerTabId != tabId) {
      _openerByTab[tabId] = openerTabId;
    }
    // The engine has already made the view and tied it to the page that asked.
    _tabs.addExisting(tabId);

    if (request.isPopup && supportsMultipleWindows) {
      _showAsPopup(
        tabId,
        openerWindowId: opener?.id ?? session.focusedWindowId,
        width: request.width,
        height: request.height,
      );
      return;
    }

    // A tab opened from a popup goes to a window that has tabs.
    final fromPopup = opener?.isPopup ?? false;
    final target = (opener != null && !fromPopup)
        ? opener
        : session.lastFocused(kind: BrowserWindowKind.normal);
    if (target == null) {
      _openWindowWith(tabId);
      return;
    }

    _commit(session.insertTab(target.id, tabId, activate: request.activate));
    if (request.activate) {
      _route(tabId);
      if (fromPopup) {
        _commit(session.focusWindow(target.id));
        _windows.raise(target.id);
      }
    }
  }
}

final browserShellProvider = Provider<BrowserShell>((ref) {
  return BrowserShell(ref)..start();
});

import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/windows/browser_shell.dart';
import 'package:flutterbird/features/windows/window_system.dart';
import 'package:ladybird/ladybird.dart';

/// Gives extensions the app's tabs and windows, and runs their background
/// pages.
///
/// A tab is a [LadybirdController], and the browser session says which window
/// each is in and which is showing, so this follows the session and reports
/// what changes. There is one of these for the app, however many windows it
/// has.
class AppBrowserBridge extends BrowserBridge {
  AppBrowserBridge(this._ref) {
    // The session is read rather than taken from the listener: when another
    // listener changes it while being told of a change, Riverpod tells the
    // rest of the new one first and the old one after.
    _ref.listen<BrowserSession>(
      browserSessionProvider,
      (_, _) => _sync(_ref.read(browserSessionProvider)),
      fireImmediately: true,
    );
    _ref.onDispose(_dispose);
  }

  final Ref _ref;
  final StreamController<TabEvent> _events =
      StreamController<TabEvent>.broadcast();
  final StreamController<WindowEvent> _windowEvents =
      StreamController<WindowEvent>.broadcast();
  final Map<int, _TabWatch> _watches = {};
  final Map<String, LadybirdController> _backgroundPages = {};
  BrowserSession _session = BrowserSession.empty;

  void _dispose() {
    for (final watch in _watches.values) {
      watch.dispose();
    }
    _watches.clear();
    for (final page in _backgroundPages.values) {
      page.dispose();
    }
    _backgroundPages.clear();
    unawaited(_events.close());
    unawaited(_windowEvents.close());
  }

  BrowserShell get _shell => _ref.read(browserShellProvider);

  WindowSystem get _system => _ref.read(windowSystemProvider);

  // ------------------------------------------------------------ tabs

  BrowserTab _describe(LadybirdController controller) {
    final window = _session.windowOfTab(controller.viewId);
    return BrowserTab(
      id: controller.viewId,
      index: window?.tabIds.indexOf(controller.viewId) ?? 0,
      active: window?.activeTabId == controller.viewId,
      url: controller.urlNotifier.value,
      title: controller.titleNotifier.value,
      isLoading: controller.isLoadingNotifier.value,
      windowId: window?.id ?? currentWindowId,
    );
  }

  void _sync(BrowserSession next) {
    final previous = _session;
    if (identical(previous, next)) return;
    _session = next;

    final before = previous.allTabIds.toSet();
    final after = next.allTabIds.toSet();

    // A window with no tabs is one being dragged away to nothing, not one
    // extensions have any business with.
    Set<int> shown(BrowserSession session) => {
      for (final window in session.windows)
        if (window.tabIds.isNotEmpty) window.id,
    };
    final windowsBefore = shown(previous);
    final windowsAfter = shown(next);

    for (final window in windows) {
      if (!windowsBefore.contains(window.id)) {
        _windowEvents.add(WindowCreated(window));
      }
    }

    for (final id in before.difference(after)) {
      _watches.remove(id)?.dispose();
      final windowId = previous.windowOfTab(id)!.id;
      _events.add(
        TabRemoved(
          id,
          windowId: windowId,
          isWindowClosing: !windowsAfter.contains(windowId),
        ),
      );
    }
    for (final id in after.difference(before)) {
      final controller = _shell.controllerFor(id);
      if (controller == null) continue;
      _watches[id] = _TabWatch(controller, this);
      _events.add(TabCreated(_describe(controller)));
    }

    for (final window in next.windows) {
      final active = window.activeTabId;
      final was = previous.window(window.id)?.activeTabId;
      if (active == null || active == was) continue;
      _events.add(
        TabActivated(
          active,
          was != null && after.contains(was) ? was : null,
          windowId: window.id,
        ),
      );
    }

    for (final id in windowsBefore.difference(windowsAfter)) {
      _windowEvents.add(WindowRemoved(id));
    }
    final focused = next.lastFocused()?.id;
    if (focused != null && focused != previous.lastFocused()?.id) {
      _windowEvents.add(WindowFocusChanged(focused));
    }
  }

  void _tabChanged(
    LadybirdController controller,
    Map<String, Object?> changes,
  ) {
    _events.add(TabUpdated(_describe(controller), changes));
  }

  @override
  List<BrowserTab> get tabs => [
    for (final id in _session.allTabIds)
      if (_shell.controllerFor(id) case final controller?)
        _describe(controller),
  ];

  @override
  int? get activeTabId => _session.focusedTabId;

  @override
  Stream<TabEvent> get tabEvents => _events.stream;

  @override
  Future<BrowserTab> createTab({
    String? url,
    bool active = true,
    int? windowId,
  }) async {
    final controller = _shell.openTab(
      windowId: windowId ?? _session.lastFocused()?.id,
      url: url,
      activate: active,
    );
    _sync(_ref.read(browserSessionProvider));
    return _describe(controller);
  }

  @override
  Future<void> updateTab(int id, {String? url, bool? active}) async {
    final controller = _shell.controllerFor(id);
    if (controller == null) return;
    if (url != null) controller.navigate(url);
    if (active == true) _shell.showTab(id);
  }

  @override
  Future<void> closeTab(int id) async => _shell.closeTab(id);

  @override
  Future<void> reloadTab(int id, {bool bypassCache = false}) async {
    _shell.controllerFor(id)?.reload();
  }

  // ------------------------------------------------------------ windows

  @override
  List<BrowserWindowInfo> get windows => [
    for (final window in _session.windows)
      if (window.tabIds.isNotEmpty) _describeWindow(window),
  ];

  BrowserWindowInfo _describeWindow(BrowserWindowModel window) {
    final frame = _system.frameOf(window.id);
    return BrowserWindowInfo(
      id: window.id,
      type: window.isPopup ? 'popup' : 'normal',
      focused: window.id == _session.lastFocused()?.id,
      state: _system.isFullscreen(window.id) ? 'fullscreen' : 'normal',
      left: frame?.left.round() ?? 0,
      top: frame?.top.round() ?? 0,
      width: frame?.width.round() ?? 1280,
      height: frame?.height.round() ?? 800,
    );
  }

  @override
  int get currentWindowId => _session.lastFocused()?.id ?? 1;

  @override
  Stream<WindowEvent> get windowEvents => _windowEvents.stream;

  @override
  Future<int> createWindow({
    String? url,
    bool popup = false,
    int? width,
    int? height,
  }) async {
    final id = popup
        ? _shell.openPopupWindow(url: url, width: width, height: height)
        : _shell.openWindow(url: url);
    _sync(_ref.read(browserSessionProvider));
    return id;
  }

  @override
  Future<void> focusWindow(int id) async {
    final session = _ref.read(browserSessionProvider);
    _ref.read(browserSessionProvider.notifier).commit(session.focusWindow(id));
    _system.raise(id);
  }

  @override
  Future<void> closeWindow(int id) async {
    // With one window, closing it would close the app.
    if (_shell.supportsMultipleWindows) _shell.closeWindow(id);
  }

  // ------------------------------------------------------------ background pages

  @override
  Future<void> startBackgroundPage(
    InstalledExtension extension,
    String url,
  ) async {
    _backgroundPages.remove(extension.uuid)?.dispose();

    // A view that no tab shows: it loads the page and runs it, and is never
    // put in the tab list.
    final page = LadybirdController();
    _backgroundPages[extension.uuid] = page;
    page.navigate(url);
  }

  @override
  Future<void> stopBackgroundPage(InstalledExtension extension) async {
    _backgroundPages.remove(extension.uuid)?.dispose();
  }
}

/// Reports a tab's changes as they happen.
class _TabWatch {
  _TabWatch(this._controller, this._bridge) {
    _controller.urlNotifier.addListener(_onUrl);
    _controller.titleNotifier.addListener(_onTitle);
    _controller.isLoadingNotifier.addListener(_onLoading);
  }

  final LadybirdController _controller;
  final AppBrowserBridge _bridge;

  void _onUrl() =>
      _bridge._tabChanged(_controller, {'url': _controller.urlNotifier.value});

  void _onTitle() => _bridge._tabChanged(_controller, {
    'title': _controller.titleNotifier.value,
  });

  void _onLoading() => _bridge._tabChanged(_controller, {
    'status': _controller.isLoadingNotifier.value ? 'loading' : 'complete',
  });

  void dispose() {
    _controller.urlNotifier.removeListener(_onUrl);
    _controller.titleNotifier.removeListener(_onTitle);
    _controller.isLoadingNotifier.removeListener(_onLoading);
  }
}

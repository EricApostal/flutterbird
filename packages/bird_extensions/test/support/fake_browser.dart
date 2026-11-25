import 'dart:async';

import 'package:bird_extensions/bird_extensions.dart';

/// A browser with tabs and windows that a test can open, change and close.
///
/// It starts with one window, numbered 1. Opening a tab in another number, or
/// calling [createWindow], makes more.
class FakeBrowser extends BrowserBridge {
  final List<BrowserTab> _tabs = [];
  final StreamController<TabEvent> _events =
      StreamController<TabEvent>.broadcast();
  final StreamController<WindowEvent> _windowEvents =
      StreamController<WindowEvent>.broadcast();
  final List<String> startedPages = [];
  final List<String> stoppedPages = [];
  int _nextId = 100;
  int _nextWindowId = 2;

  final Map<int, String> _windowTypes = {1: 'normal'};
  final Map<int, int> _activeByWindow = {};
  int _current = 1;

  @override
  List<BrowserTab> get tabs => List.unmodifiable(_tabs);

  @override
  int? get activeTabId => _activeByWindow[_current];

  @override
  Stream<TabEvent> get tabEvents => _events.stream;

  @override
  Stream<WindowEvent> get windowEvents => _windowEvents.stream;

  @override
  int get currentWindowId => _current;

  @override
  List<BrowserWindowInfo> get windows => [
    for (final entry in _windowTypes.entries) _window(entry.key),
  ];

  BrowserWindowInfo _window(int id) => BrowserWindowInfo(
    id: id,
    type: _windowTypes[id]!,
    focused: id == _current,
  );

  BrowserTab _make(
    int id,
    int index,
    int windowId,
    String url, {
    String title = '',
  }) => BrowserTab(
    id: id,
    index: index,
    active: id == _activeByWindow[windowId],
    url: url,
    title: title,
    isLoading: false,
    windowId: windowId,
  );

  /// Opens a tab as the user would.
  BrowserTab open(
    String url, {
    int? id,
    String title = '',
    bool activate = true,
    int windowId = 1,
  }) {
    final tabId = id ?? _nextId++;
    _windowTypes.putIfAbsent(windowId, () => 'normal');
    final previous = _activeByWindow[windowId];
    if (activate) _activeByWindow[windowId] = tabId;
    _tabs.add(_make(tabId, _tabs.length, windowId, url, title: title));
    _refresh();
    final tab = _tabs.firstWhere((tab) => tab.id == tabId);
    _events.add(TabCreated(tab));
    if (activate && previous != tabId) {
      _events.add(TabActivated(tabId, previous, windowId: windowId));
    }
    return tab;
  }

  /// Brings a window to the front, as the user would.
  void focus(int windowId) {
    _current = windowId;
    _windowEvents.add(WindowFocusChanged(windowId));
  }

  void navigate(int id, String url, {String? title}) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    final old = _tabs[index];
    _tabs[index] = BrowserTab(
      id: id,
      index: old.index,
      active: old.active,
      url: url,
      title: title ?? old.title,
      isLoading: false,
      windowId: old.windowId,
    );
    _events.add(TabUpdated(_tabs[index], {'url': url, 'title': ?title}));
  }

  void _refresh() {
    final nextIndex = <int, int>{};
    for (var i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      final index = nextIndex[tab.windowId] ?? 0;
      nextIndex[tab.windowId] = index + 1;
      _tabs[i] = _make(tab.id, index, tab.windowId, tab.url, title: tab.title);
    }
  }

  @override
  Future<BrowserTab> createTab({
    String? url,
    bool active = true,
    int? windowId,
  }) async => open(
    url ?? 'about:blank',
    activate: active,
    windowId: windowId ?? _current,
  );

  @override
  Future<int> createWindow({
    String? url,
    bool popup = false,
    int? width,
    int? height,
  }) async {
    final id = _nextWindowId++;
    _windowTypes[id] = popup ? 'popup' : 'normal';
    _current = id;
    _windowEvents.add(WindowCreated(_window(id)));
    open(url ?? 'about:blank', windowId: id);
    return id;
  }

  @override
  Future<void> focusWindow(int id) async => focus(id);

  @override
  Future<void> closeWindow(int id) async {
    for (final tab in _tabs.where((tab) => tab.windowId == id).toList()) {
      await closeTab(tab.id);
    }
    _windowTypes.remove(id);
    if (_current == id && _windowTypes.isNotEmpty) {
      _current = _windowTypes.keys.first;
    }
    _windowEvents.add(WindowRemoved(id));
  }

  @override
  Future<void> updateTab(int id, {String? url, bool? active}) async {
    if (url != null) navigate(id, url);
    if (active == true) {
      final windowId = _tabs.firstWhere((tab) => tab.id == id).windowId;
      final previous = _activeByWindow[windowId];
      _activeByWindow[windowId] = id;
      _refresh();
      _events.add(TabActivated(id, previous, windowId: windowId));
    }
  }

  @override
  Future<void> closeTab(int id) async {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    final windowId = _tabs.removeAt(index).windowId;
    if (_activeByWindow[windowId] == id) {
      final left = _tabs.where((tab) => tab.windowId == windowId);
      if (left.isEmpty) {
        _activeByWindow.remove(windowId);
      } else {
        _activeByWindow[windowId] = left.last.id;
      }
    }
    _refresh();
    _events.add(TabRemoved(id, windowId: windowId));
  }

  final List<int> reloaded = [];

  @override
  Future<void> reloadTab(int id, {bool bypassCache = false}) async =>
      reloaded.add(id);

  @override
  Future<void> startBackgroundPage(
    InstalledExtension extension,
    String url,
  ) async => startedPages.add(url);

  @override
  Future<void> stopBackgroundPage(InstalledExtension extension) async =>
      stoppedPages.add(extension.uuid);
}

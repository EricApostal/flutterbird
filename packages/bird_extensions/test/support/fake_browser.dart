import 'dart:async';

import 'package:bird_extensions/bird_extensions.dart';

/// A browser with tabs that a test can open, change and close.
class FakeBrowser extends BrowserBridge {
  final List<BrowserTab> _tabs = [];
  final StreamController<TabEvent> _events =
      StreamController<TabEvent>.broadcast();
  final List<String> startedPages = [];
  final List<String> stoppedPages = [];
  int _nextId = 100;
  int? _active;

  @override
  List<BrowserTab> get tabs => List.unmodifiable(_tabs);

  @override
  int? get activeTabId => _active;

  @override
  Stream<TabEvent> get tabEvents => _events.stream;

  BrowserTab _make(int id, int index, String url, {String title = ''}) =>
      BrowserTab(
        id: id,
        index: index,
        active: id == _active,
        url: url,
        title: title,
        isLoading: false,
      );

  /// Opens a tab as the user would.
  BrowserTab open(
    String url, {
    int? id,
    String title = '',
    bool activate = true,
  }) {
    final tabId = id ?? _nextId++;
    final previous = _active;
    if (activate) _active = tabId;
    _tabs.add(_make(tabId, _tabs.length, url, title: title));
    _refresh();
    final tab = _tabs.last;
    _events.add(TabCreated(tab));
    if (activate && previous != tabId) {
      _events.add(TabActivated(tabId, previous));
    }
    return tab;
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
    );
    _events.add(TabUpdated(_tabs[index], {'url': url, 'title': ?title}));
  }

  void _refresh() {
    for (var i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      _tabs[i] = BrowserTab(
        id: tab.id,
        index: i,
        active: tab.id == _active,
        url: tab.url,
        title: tab.title,
        isLoading: tab.isLoading,
      );
    }
  }

  @override
  Future<BrowserTab> createTab({String? url, bool active = true}) async =>
      open(url ?? 'about:blank', activate: active);

  @override
  Future<void> updateTab(int id, {String? url, bool? active}) async {
    if (url != null) navigate(id, url);
    if (active == true) {
      final previous = _active;
      _active = id;
      _refresh();
      _events.add(TabActivated(id, previous));
    }
  }

  @override
  Future<void> closeTab(int id) async {
    _tabs.removeWhere((tab) => tab.id == id);
    if (_active == id) _active = _tabs.isEmpty ? null : _tabs.last.id;
    _refresh();
    _events.add(TabRemoved(id));
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

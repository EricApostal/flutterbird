import 'dart:async';

import 'package:bird_extensions/bird_extensions.dart';

import 'engine.dart';

class _Tab {
  _Tab(this.url);
  String url;
  bool isLoading = true;
}

/// The least browser extensions can run in: tabs that are views of the engine,
/// and hidden views for background pages. The app's own bridge does this over
/// its tab list.
class HeadlessBrowser extends BrowserBridge {
  HeadlessBrowser(this.engine) {
    _views = engine.viewEvents.listen(_viewChanged);
  }

  final Engine engine;
  final Map<int, _Tab> _tabs = {};
  final Map<String, int> _backgrounds = {};
  final _events = StreamController<TabEvent>.broadcast();
  late final StreamSubscription<ViewEvent> _views;
  int? _active;

  @override
  List<BrowserTab> get tabs => [
    for (final (index, entry) in _tabs.entries.indexed)
      _describe(entry.key, entry.value, index),
  ];

  BrowserTab _describe(int id, _Tab tab, int index) => BrowserTab(
    id: id,
    index: index,
    active: id == _active,
    url: tab.url,
    title: '',
    isLoading: tab.isLoading,
  );

  @override
  int? get activeTabId => _active;

  @override
  Stream<TabEvent> get tabEvents => _events.stream;

  void _viewChanged(ViewEvent event) {
    final tab = _tabs[event.view];
    if (tab == null) return;
    final changes = <String, Object?>{};
    if (event.url case final url?) changes['url'] = tab.url = url;
    if (event.loading case final loading?) {
      tab.isLoading = loading;
      changes['status'] = loading ? 'loading' : 'complete';
    }
    _events.add(TabUpdated(this.tab(event.view)!, changes));
  }

  @override
  Future<BrowserTab> createTab({
    String? url,
    bool active = true,
    int? windowId,
  }) async {
    final view = await engine.createView();
    _tabs[view] = _Tab(url ?? 'about:blank');
    final previous = _active;
    if (active || previous == null) _active = view;
    final created = tab(view)!;
    _events.add(TabCreated(created));
    if (_active == view) _events.add(TabActivated(view, previous));
    if (url != null) engine.navigate(view, url);
    return created;
  }

  @override
  Future<void> updateTab(int id, {String? url, bool? active}) async {
    if (url != null) engine.navigate(id, url);
    if (active == true) {
      final previous = _active;
      _active = id;
      _events.add(TabActivated(id, previous));
    }
  }

  @override
  Future<void> closeTab(int id) async {
    if (_tabs.remove(id) == null) return;
    engine.destroyView(id);
    if (_active == id) _active = _tabs.keys.lastOrNull;
    _events.add(TabRemoved(id));
  }

  @override
  Future<void> reloadTab(int id, {bool bypassCache = false}) async {
    final url = _tabs[id]?.url;
    if (url != null) engine.navigate(id, url);
  }

  @override
  Future<void> startBackgroundPage(
    InstalledExtension extension,
    String url,
  ) async {
    await stopBackgroundPage(extension);
    final view = await engine.createView();
    _backgrounds[extension.uuid] = view;
    engine.navigate(view, url);
  }

  @override
  Future<void> stopBackgroundPage(InstalledExtension extension) async {
    final view = _backgrounds.remove(extension.uuid);
    if (view != null) engine.destroyView(view);
  }

  Future<void> dispose() async {
    await _views.cancel();
    await _events.close();
  }
}

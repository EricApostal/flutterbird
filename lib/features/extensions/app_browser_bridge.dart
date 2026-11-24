import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/router/controller.dart';
import 'package:ladybird/ladybird.dart';

/// Gives extensions the app's tabs, and runs their background pages.
///
/// A tab is a [LadybirdController], and which one is showing is the route the
/// app is on, so this reads both and reports what changes.
class AppBrowserBridge extends BrowserBridge {
  AppBrowserBridge(this._ref) {
    _ref.listen(
      browserTabControllerProvider,
      (_, next) => _sync(next),
      fireImmediately: true,
    );
    routerController.routerDelegate.addListener(_onRoute);
    _onRoute();
    _ref.onDispose(_dispose);
  }

  static final RegExp _tabRoute = RegExp(r'^/browser/tab/(\d+)');

  final Ref _ref;
  final StreamController<TabEvent> _events = StreamController<TabEvent>.broadcast();
  final Map<int, _TabWatch> _watches = {};
  final Map<String, LadybirdController> _backgroundPages = {};
  List<LadybirdController> _controllers = const [];
  int? _active;

  void _dispose() {
    routerController.routerDelegate.removeListener(_onRoute);
    for (final watch in _watches.values) {
      watch.dispose();
    }
    _watches.clear();
    for (final page in _backgroundPages.values) {
      page.dispose();
    }
    _backgroundPages.clear();
    unawaited(_events.close());
  }

  // ------------------------------------------------------------ tabs

  BrowserTab _describe(LadybirdController controller) => BrowserTab(
    id: controller.viewId,
    index: _controllers.indexOf(controller),
    active: controller.viewId == _active,
    url: controller.urlNotifier.value,
    title: controller.titleNotifier.value,
    isLoading: controller.isLoadingNotifier.value,
  );

  void _sync(List<LadybirdController> next) {
    final before = {for (final c in _controllers) c.viewId};
    final after = {for (final c in next) c.viewId};
    _controllers = next;

    for (final id in before.difference(after)) {
      _watches.remove(id)?.dispose();
      _events.add(TabRemoved(id));
    }
    for (final controller in next) {
      if (before.contains(controller.viewId)) continue;
      _watches[controller.viewId] = _TabWatch(controller, this);
      _events.add(TabCreated(_describe(controller)));
    }
  }

  void _onRoute() {
    final path = routerController.routeInformationProvider.value.uri.path;
    final match = _tabRoute.firstMatch(path);
    final now = match == null ? _active : int.parse(match.group(1)!);
    if (now == _active) return;

    final previous = _active;
    _active = now;
    if (now != null) _events.add(TabActivated(now, previous));
  }

  void _tabChanged(LadybirdController controller, Map<String, Object?> changes) {
    _events.add(TabUpdated(_describe(controller), changes));
  }

  LadybirdController? _controller(int id) {
    for (final controller in _controllers) {
      if (controller.viewId == id) return controller;
    }
    return null;
  }

  @override
  List<BrowserTab> get tabs => [for (final c in _controllers) _describe(c)];

  @override
  int? get activeTabId => _active;

  @override
  Stream<TabEvent> get tabEvents => _events.stream;

  @override
  Future<BrowserTab> createTab({String? url, bool active = true}) async {
    final controller = _ref.read(browserTabControllerProvider.notifier).add();
    _sync(_ref.read(browserTabControllerProvider));
    if (url != null) controller.navigate(url);
    if (active) routerController.go('/browser/tab/${controller.viewId}');
    return _describe(controller);
  }

  @override
  Future<void> updateTab(int id, {String? url, bool? active}) async {
    final controller = _controller(id);
    if (controller == null) return;
    if (url != null) controller.navigate(url);
    if (active == true) routerController.go('/browser/tab/$id');
  }

  @override
  Future<void> closeTab(int id) async {
    final tabs = _ref.read(browserTabControllerProvider);
    final index = tabs.indexWhere((tab) => tab.viewId == id);
    if (index < 0) return;

    // Closing the tab on screen shows its neighbour.
    if (_active == id && tabs.length > 1) {
      final neighbour = tabs[index == 0 ? 1 : index - 1];
      routerController.go('/browser/tab/${neighbour.viewId}');
    }
    _ref.read(browserTabControllerProvider.notifier).remove(id);
  }

  @override
  Future<void> reloadTab(int id, {bool bypassCache = false}) async {
    _controller(id)?.reload();
  }

  // ------------------------------------------------------------ background pages

  @override
  Future<void> startBackgroundPage(InstalledExtension extension, String url) async {
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

  void _onUrl() => _bridge._tabChanged(_controller, {'url': _controller.urlNotifier.value});

  void _onTitle() => _bridge._tabChanged(_controller, {'title': _controller.titleNotifier.value});

  void _onLoading() => _bridge._tabChanged(_controller, {
    'status': _controller.isLoadingNotifier.value ? 'loading' : 'complete',
  });

  void dispose() {
    _controller.urlNotifier.removeListener(_onUrl);
    _controller.titleNotifier.removeListener(_onTitle);
    _controller.isLoadingNotifier.removeListener(_onLoading);
  }
}

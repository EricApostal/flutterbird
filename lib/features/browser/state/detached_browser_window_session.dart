import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:ladybird/ladybird.dart';

class DetachedBrowserWindowSession extends ChangeNotifier {
  DetachedBrowserWindowSession({required LadybirdController initialTab})
    : _tabs = <LadybirdController>[initialTab],
      _currentViewId = initialTab.viewId {
    _bindActiveTabTitleListener();
  }

  final List<LadybirdController> _tabs;
  int _currentViewId;

  VoidCallback? onWindowTitleChanged;
  VoidCallback? onEmpty;

  VoidCallback? _activeTitleListener;

  UnmodifiableListView<LadybirdController> get tabs =>
      UnmodifiableListView<LadybirdController>(_tabs);

  int get currentViewId => _currentViewId;

  LadybirdController? get currentTab =>
      _tabs.firstWhereOrNull((tab) => tab.viewId == _currentViewId);

  String get currentWindowTitle {
    final title = currentTab?.titleNotifier.value.trim() ?? '';
    return title.isEmpty ? 'Tab' : title;
  }

  void selectTab(int viewId) {
    if (_currentViewId == viewId) return;
    if (!_tabs.any((tab) => tab.viewId == viewId)) return;

    _currentViewId = viewId;
    _bindActiveTabTitleListener();
    onWindowTitleChanged?.call();
    notifyListeners();
  }

  LadybirdController addTab() {
    final controller = LadybirdController();
    _tabs.add(controller);
    _currentViewId = controller.viewId;
    _bindActiveTabTitleListener();
    onWindowTitleChanged?.call();
    notifyListeners();
    return controller;
  }

  LadybirdController? takeTab(int viewId) {
    final index = _tabs.indexWhere((tab) => tab.viewId == viewId);
    if (index < 0) return null;

    final removedTab = _tabs.removeAt(index);
    final wasCurrent = removedTab.viewId == _currentViewId;

    if (_tabs.isEmpty) {
      _unbindActiveTabTitleListener();
      onEmpty?.call();
      notifyListeners();
      return removedTab;
    }

    if (wasCurrent) {
      final fallbackIndex = index == 0 ? 0 : index - 1;
      _currentViewId = _tabs[fallbackIndex].viewId;
      _bindActiveTabTitleListener();
      onWindowTitleChanged?.call();
    }

    notifyListeners();
    return removedTab;
  }

  void insertTabAt(
    int index,
    LadybirdController controller, {
    bool select = false,
  }) {
    final clampedIndex = index.clamp(0, _tabs.length);
    _tabs.insert(clampedIndex, controller);
    if (select || _tabs.length == 1) {
      _currentViewId = controller.viewId;
      _bindActiveTabTitleListener();
      onWindowTitleChanged?.call();
    }
    notifyListeners();
  }

  void reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tabs.length) return;
    if (newIndex < 0 || newIndex >= _tabs.length) return;
    if (oldIndex == newIndex) return;

    final tab = _tabs.removeAt(oldIndex);
    _tabs.insert(newIndex, tab);
    notifyListeners();
  }

  void closeTab(int viewId) {
    final index = _tabs.indexWhere((tab) => tab.viewId == viewId);
    if (index < 0) return;

    final removedTab = _tabs.removeAt(index);
    final wasCurrent = removedTab.viewId == _currentViewId;
    removedTab.dispose();

    if (_tabs.isEmpty) {
      _unbindActiveTabTitleListener();
      onEmpty?.call();
      notifyListeners();
      return;
    }

    if (wasCurrent) {
      final fallbackIndex = index == 0 ? 0 : index - 1;
      _currentViewId = _tabs[fallbackIndex].viewId;
    }

    _bindActiveTabTitleListener();
    onWindowTitleChanged?.call();
    notifyListeners();
  }

  void _bindActiveTabTitleListener() {
    _unbindActiveTabTitleListener();

    final activeTab = currentTab;
    if (activeTab == null) return;

    void handleTitleChange() {
      onWindowTitleChanged?.call();
      notifyListeners();
    }

    _activeTitleListener = handleTitleChange;
    activeTab.titleNotifier.addListener(handleTitleChange);
  }

  void _unbindActiveTabTitleListener() {
    final listener = _activeTitleListener;
    if (listener == null) return;

    final activeTab = currentTab;
    if (activeTab != null) {
      activeTab.titleNotifier.removeListener(listener);
    }
    _activeTitleListener = null;
  }

  @override
  void dispose() {
    _unbindActiveTabTitleListener();
    for (final tab in _tabs) {
      tab.dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}

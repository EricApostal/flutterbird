// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'browser.dart';

part 'window_layout.g.dart';

const int mainBrowserWindowId = 0;

@immutable
class BrowserWindowState {
  final int id;
  final List<int> tabIds;
  final int? activeViewId;
  final RegularWindowController? nativeWindowController;

  const BrowserWindowState({
    required this.id,
    required this.tabIds,
    required this.activeViewId,
    this.nativeWindowController,
  });

  bool get isMain => id == mainBrowserWindowId;

  BrowserWindowState copyWith({
    List<int>? tabIds,
    int? activeViewId,
    bool clearActiveViewId = false,
  }) {
    return BrowserWindowState(
      id: id,
      tabIds: tabIds ?? this.tabIds,
      activeViewId: clearActiveViewId
          ? null
          : (activeViewId ?? this.activeViewId),
      nativeWindowController: nativeWindowController,
    );
  }
}

@immutable
class BrowserWindowLayoutState {
  final int nextDetachedWindowId;
  final List<BrowserWindowState> windows;

  const BrowserWindowLayoutState({
    required this.nextDetachedWindowId,
    required this.windows,
  });

  factory BrowserWindowLayoutState.initial() {
    return const BrowserWindowLayoutState(
      nextDetachedWindowId: 1,
      windows: [
        BrowserWindowState(
          id: mainBrowserWindowId,
          tabIds: [],
          activeViewId: null,
        ),
      ],
    );
  }

  BrowserWindowState? windowById(int id) {
    for (final window in windows) {
      if (window.id == id) {
        return window;
      }
    }
    return null;
  }

  List<BrowserWindowState> get detachedWindows {
    return windows.where((window) => !window.isMain).toList();
  }

  BrowserWindowLayoutState copyWith({
    int? nextDetachedWindowId,
    List<BrowserWindowState>? windows,
  }) {
    return BrowserWindowLayoutState(
      nextDetachedWindowId: nextDetachedWindowId ?? this.nextDetachedWindowId,
      windows: windows ?? this.windows,
    );
  }
}

@Riverpod(keepAlive: true)
class BrowserWindowLayout extends _$BrowserWindowLayout {
  @override
  BrowserWindowLayoutState build() {
    return BrowserWindowLayoutState.initial();
  }

  void ensureMainTab(int viewId) {
    final mainWindow = state.windowById(mainBrowserWindowId);
    if (mainWindow == null) {
      state = BrowserWindowLayoutState(
        nextDetachedWindowId: state.nextDetachedWindowId,
        windows: [
          BrowserWindowState(
            id: mainBrowserWindowId,
            tabIds: [viewId],
            activeViewId: viewId,
          ),
        ],
      );
      return;
    }

    if (mainWindow.tabIds.contains(viewId)) {
      if (mainWindow.activeViewId != viewId) {
        setActiveTab(mainBrowserWindowId, viewId);
      }
      return;
    }

    addTabToWindow(mainBrowserWindowId, viewId, makeActive: true);
  }

  void addTabToWindow(int windowId, int viewId, {bool makeActive = true}) {
    final updatedWindows = <BrowserWindowState>[];
    for (final window in state.windows) {
      if (window.id != windowId) {
        updatedWindows.add(window);
        continue;
      }

      if (window.tabIds.contains(viewId)) {
        updatedWindows.add(
          window.copyWith(
            activeViewId: makeActive ? viewId : window.activeViewId,
          ),
        );
      } else {
        final tabIds = [...window.tabIds, viewId];
        updatedWindows.add(
          window.copyWith(
            tabIds: tabIds,
            activeViewId: makeActive
                ? viewId
                : (window.activeViewId ?? tabIds.first),
          ),
        );
      }
    }

    state = state.copyWith(windows: updatedWindows);
  }

  void setActiveTab(int windowId, int viewId) {
    final updatedWindows = <BrowserWindowState>[];
    for (final window in state.windows) {
      if (window.id != windowId) {
        updatedWindows.add(window);
        continue;
      }

      if (!window.tabIds.contains(viewId)) {
        updatedWindows.add(window);
        continue;
      }

      updatedWindows.add(window.copyWith(activeViewId: viewId));
    }

    state = state.copyWith(windows: updatedWindows);
  }

  void reorderTab(int windowId, int oldIndex, int newIndex) {
    final window = state.windowById(windowId);
    if (window == null || window.tabIds.length < 2) {
      return;
    }
    if (oldIndex < 0 || oldIndex >= window.tabIds.length) {
      return;
    }

    final adjustedIndex = math.min(
      math.max(newIndex, 0),
      window.tabIds.length - 1,
    );
    if (adjustedIndex == oldIndex) {
      return;
    }

    final reordered = [...window.tabIds];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(adjustedIndex, item);

    final updatedWindows = <BrowserWindowState>[];
    for (final current in state.windows) {
      if (current.id == windowId) {
        updatedWindows.add(current.copyWith(tabIds: reordered));
      } else {
        updatedWindows.add(current);
      }
    }

    state = state.copyWith(windows: updatedWindows);
  }

  int? fallbackTabAfterClose(int windowId, int closingViewId) {
    final window = state.windowById(windowId);
    if (window == null) {
      return null;
    }

    final index = window.tabIds.indexOf(closingViewId);
    if (index == -1 || window.tabIds.length == 1) {
      return null;
    }

    final fallbackIndex = index == 0 ? 1 : index - 1;
    return window.tabIds[fallbackIndex];
  }

  void removeTab(int viewId) {
    final updatedWindows = <BrowserWindowState>[];

    for (final window in state.windows) {
      if (!window.tabIds.contains(viewId)) {
        updatedWindows.add(window);
        continue;
      }

      final filteredTabs = window.tabIds.where((id) => id != viewId).toList();
      if (!window.isMain && filteredTabs.isEmpty) {
        window.nativeWindowController?.destroy();
        continue;
      }

      final nextActive = filteredTabs.isEmpty
          ? null
          : (filteredTabs.contains(window.activeViewId)
                ? window.activeViewId
                : filteredTabs.first);

      updatedWindows.add(
        window.copyWith(
          tabIds: filteredTabs,
          activeViewId: nextActive,
          clearActiveViewId: filteredTabs.isEmpty,
        ),
      );
    }

    state = state.copyWith(windows: updatedWindows);
  }

  int? detachTab({required int tabId, required int fromWindowId}) {
    final sourceWindow = state.windowById(fromWindowId);
    if (sourceWindow == null) {
      return null;
    }
    if (!sourceWindow.tabIds.contains(tabId)) {
      return null;
    }

    var replacementMainTabId = -1;
    if (sourceWindow.tabIds.length <= 1) {
      if (fromWindowId != mainBrowserWindowId) {
        return null;
      }

      final replacementController = ref
          .read(browserTabControllerProvider.notifier)
          .add();
      replacementMainTabId = replacementController.viewId;
    }

    final detachedController = RegularWindowController(
      preferredSize: const Size(900, 700),
      title: 'Detached Tab',
    );

    final remainingTabs = sourceWindow.tabIds
        .where((id) => id != tabId)
        .toList();
    if (replacementMainTabId != -1) {
      remainingTabs.add(replacementMainTabId);
    }
    final sourceActive = sourceWindow.activeViewId == tabId
        ? remainingTabs.first
        : sourceWindow.activeViewId;

    final detachedWindowId = state.nextDetachedWindowId;

    final updatedWindows = <BrowserWindowState>[];
    for (final window in state.windows) {
      if (window.id == fromWindowId) {
        updatedWindows.add(
          window.copyWith(tabIds: remainingTabs, activeViewId: sourceActive),
        );
      } else {
        updatedWindows.add(window);
      }
    }

    updatedWindows.add(
      BrowserWindowState(
        id: detachedWindowId,
        tabIds: [tabId],
        activeViewId: tabId,
        nativeWindowController: detachedController,
      ),
    );

    state = state.copyWith(
      nextDetachedWindowId: detachedWindowId + 1,
      windows: updatedWindows,
    );

    return detachedWindowId;
  }

  bool mergeTabToWindow({
    required int tabId,
    required int fromWindowId,
    required int toWindowId,
  }) {
    if (fromWindowId == toWindowId) {
      return false;
    }

    final sourceWindow = state.windowById(fromWindowId);
    final targetWindow = state.windowById(toWindowId);
    if (sourceWindow == null || targetWindow == null) {
      return false;
    }
    if (!sourceWindow.tabIds.contains(tabId)) {
      return false;
    }

    final sourceRemainingTabs = sourceWindow.tabIds
        .where((id) => id != tabId)
        .toList();
    final nextSourceActive = sourceRemainingTabs.isEmpty
        ? null
        : (sourceRemainingTabs.contains(sourceWindow.activeViewId)
              ? sourceWindow.activeViewId
              : sourceRemainingTabs.first);

    if (sourceWindow.isMain && sourceRemainingTabs.isEmpty) {
      return false;
    }

    final mergedTargetTabs = [...targetWindow.tabIds];
    if (!mergedTargetTabs.contains(tabId)) {
      mergedTargetTabs.add(tabId);
    }

    final updatedWindows = <BrowserWindowState>[];
    for (final window in state.windows) {
      if (window.id == toWindowId) {
        updatedWindows.add(
          window.copyWith(tabIds: mergedTargetTabs, activeViewId: tabId),
        );
        continue;
      }

      if (window.id != fromWindowId) {
        updatedWindows.add(window);
        continue;
      }

      if (sourceRemainingTabs.isEmpty) {
        window.nativeWindowController?.destroy();
        continue;
      }

      updatedWindows.add(
        window.copyWith(
          tabIds: sourceRemainingTabs,
          activeViewId: nextSourceActive,
          clearActiveViewId: sourceRemainingTabs.isEmpty,
        ),
      );
    }

    state = state.copyWith(windows: updatedWindows);
    return true;
  }

  bool mergeTabToMain({required int tabId, required int fromWindowId}) {
    return mergeTabToWindow(
      tabId: tabId,
      fromWindowId: fromWindowId,
      toWindowId: mainBrowserWindowId,
    );
  }
}

@Riverpod(keepAlive: true)
BrowserWindowState? browserWindowState(Ref ref, int windowId) {
  final layout = ref.watch(browserWindowLayoutProvider);
  return layout.windowById(windowId);
}

@Riverpod(keepAlive: true)
List<int> browserWindowTabIds(Ref ref, int windowId) {
  final window = ref.watch(browserWindowStateProvider(windowId));
  return window?.tabIds ?? const <int>[];
}

@Riverpod(keepAlive: true)
int? browserWindowActiveTabId(Ref ref, int windowId) {
  final window = ref.watch(browserWindowStateProvider(windowId));
  return window?.activeViewId;
}

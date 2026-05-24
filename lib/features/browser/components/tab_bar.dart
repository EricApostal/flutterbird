import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/tab.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_toolbox/window_toolbox.dart';

class BrowserTabBar extends ConsumerStatefulWidget {
  final int windowId;
  final int currentViewId;

  const BrowserTabBar({
    super.key,
    required this.windowId,
    required this.currentViewId,
  });

  @override
  ConsumerState<BrowserTabBar> createState() => _BrowserTabBarState();
}

class _BrowserTabBarState extends ConsumerState<BrowserTabBar> {
  final GlobalKey _tabStripKey = GlobalKey();

  bool _isPointerInsideTabStrip(Offset globalPosition) {
    final context = _tabStripKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return true;
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    return rect.inflate(6).contains(globalPosition);
  }

  void _handleDetachOnDragOut({
    required _DraggedTabData dragData,
    required DragUpdateDetails details,
    required BrowserWindowLayout layoutController,
  }) {
    if (widget.windowId != mainBrowserWindowId) {
      return;
    }
    if (dragData.currentWindowId != mainBrowserWindowId) {
      return;
    }
    if (_isPointerInsideTabStrip(details.globalPosition)) {
      return;
    }

    final detachedWindowId = layoutController.detachTab(
      tabId: dragData.tabId,
      fromWindowId: mainBrowserWindowId,
    );
    if (detachedWindowId == null) {
      return;
    }

    dragData.currentWindowId = detachedWindowId;

    final activeMainTab = ref
        .read(browserWindowLayoutProvider)
        .windowById(mainBrowserWindowId)
        ?.activeViewId;
    if (activeMainTab != null) {
      context.go('/browser/tab/$activeMainTab');
    }
  }

  void _handleMergeOnMainStripHover({
    required _DraggedTabData dragData,
    required BrowserWindowLayout layoutController,
  }) {
    if (widget.windowId != mainBrowserWindowId) {
      return;
    }
    if (dragData.currentWindowId == mainBrowserWindowId) {
      return;
    }

    final merged = layoutController.mergeTabToMain(
      tabId: dragData.tabId,
      fromWindowId: dragData.currentWindowId,
    );
    if (!merged) {
      return;
    }

    dragData.currentWindowId = mainBrowserWindowId;
    layoutController.setActiveTab(mainBrowserWindowId, dragData.tabId);
    context.go('/browser/tab/${dragData.tabId}');
  }

  Widget _buildTabStripDragTarget({
    required BrowserWindowLayout layoutController,
    required List<LadybirdController> tabs,
    required List<int> windowTabIds,
    required int resolvedCurrentViewId,
    required bool isDetachedWindow,
    required List<LadybirdController> allTabs,
  }) {
    final strip = DragTarget<_DraggedTabData>(
      key: _tabStripKey,
      onMove: (details) {
        _handleMergeOnMainStripHover(
          dragData: details.data,
          layoutController: layoutController,
        );
      },
      builder: (context, candidateData, rejectedData) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int index = 0; index < tabs.length; index++)
                _TabDropTarget(
                  windowId: widget.windowId,
                  targetTabId: tabs[index].viewId,
                  onReorderAccepted: (dragData) {
                    final oldIndex = windowTabIds.indexOf(dragData.tabId);
                    if (oldIndex == -1 || oldIndex == index) {
                      return;
                    }
                    layoutController.reorderTab(
                      widget.windowId,
                      oldIndex,
                      index,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: _DraggableBrowserTab(
                      tabId: tabs[index].viewId,
                      selected: tabs[index].viewId == resolvedCurrentViewId,
                      initialWindowId: widget.windowId,
                      onSelected: () {
                        layoutController.setActiveTab(
                          widget.windowId,
                          tabs[index].viewId,
                        );
                        if (!isDetachedWindow) {
                          context.go('/browser/tab/${tabs[index].viewId}');
                        }
                      },
                      onClose: () {
                        HapticFeedback.lightImpact();
                        if (allTabs.length == 1) {
                          exit(0);
                        }

                        final fallbackTab = layoutController
                            .fallbackTabAfterClose(
                              widget.windowId,
                              tabs[index].viewId,
                            );

                        if (tabs[index].viewId == resolvedCurrentViewId &&
                            fallbackTab != null) {
                          if (isDetachedWindow) {
                            layoutController.setActiveTab(
                              widget.windowId,
                              fallbackTab,
                            );
                          } else {
                            context.go('/browser/tab/$fallbackTab');
                          }
                        }

                        layoutController.removeTab(tabs[index].viewId);
                        ref
                            .read(browserTabControllerProvider.notifier)
                            .remove(tabs[index].viewId);
                      },
                      onDragUpdate: (dragData, details) {
                        _handleDetachOnDragOut(
                          dragData: dragData,
                          details: details,
                          layoutController: layoutController,
                        );
                      },
                    ),
                  ),
                ),
              _TabEndDropTarget(
                windowId: widget.windowId,
                onReorderAccepted: (dragData) {
                  final oldIndex = windowTabIds.indexOf(dragData.tabId);
                  if (oldIndex == -1) {
                    return;
                  }
                  layoutController.reorderTab(
                    widget.windowId,
                    oldIndex,
                    tabs.length - 1,
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 20),
                onPressed: () {
                  final controller = ref
                      .read(browserTabControllerProvider.notifier)
                      .add();

                  layoutController.addTabToWindow(
                    widget.windowId,
                    controller.viewId,
                    makeActive: true,
                  );

                  if (!isDetachedWindow) {
                    context.go('/browser/tab/${controller.viewId}');
                  }
                },
              ),
            ],
          ),
        );
      },
    );

    if (isDetachedWindow) {
      return WindowDragExcludeArea(child: strip);
    }
    return strip;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layoutController = ref.read(browserWindowLayoutProvider.notifier);

    final allTabs = ref.watch(browserTabControllerProvider);
    final windowTabIds = ref.watch(
      browserWindowTabIdsProvider(widget.windowId),
    );
    final tabById = {for (final tab in allTabs) tab.viewId: tab};
    final tabs = windowTabIds
        .map((viewId) => tabById[viewId])
        .whereType<LadybirdController>()
        .toList();

    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final resolvedCurrentViewId = windowTabIds.contains(widget.currentViewId)
        ? widget.currentViewId
        : tabs.first.viewId;

    final currentTabController = ref.watch(
      browserTabProvider(resolvedCurrentViewId),
    );

    final isDetachedWindow = widget.windowId != mainBrowserWindowId;
    final doLeftPadding = Platform.isMacOS;

    return Column(
      children: [
        if (isDetachedWindow)
          Container(
            width: double.infinity,
            color: theme.colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Drag tabs out to detach. Drag back over the main tab strip to merge.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        SizedBox(
          height: 45,
          child: Stack(
            children: [
              Positioned.fill(
                child: widget.windowId == mainBrowserWindowId
                    ? const DragToMoveArea(child: SizedBox.expand())
                    : const WindowDragArea(child: SizedBox.expand()),
              ),
              Padding(
                padding: EdgeInsets.only(left: doLeftPadding ? 80 : 8),
                child: _buildTabStripDragTarget(
                  layoutController: layoutController,
                  tabs: tabs,
                  windowTabIds: windowTabIds,
                  resolvedCurrentViewId: resolvedCurrentViewId,
                  isDetachedWindow: isDetachedWindow,
                  allTabs: allTabs,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => currentTabController?.goBack(),
                splashRadius: 20,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: () => currentTabController?.goForward(),
                splashRadius: 20,
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => currentTabController?.reload(),
                splashRadius: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: currentTabController == null
                    ? const SizedBox.shrink()
                    : ValueListenableBuilder<String>(
                        valueListenable: currentTabController.urlNotifier,
                        builder: (context, url, child) {
                          if (currentTabController.textController.text != url &&
                              !FocusScope.of(context).hasFocus) {
                            currentTabController.textController.text = url;
                          }
                          return TextField(
                            onSubmitted: currentTabController.navigate,
                            controller: currentTabController.textController,
                            decoration: _buildInputDecoration(context),
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(BuildContext context) {
    final theme = Theme.of(context);
    const radius = 12.0;

    return InputDecoration(
      hintText: 'Search',
      filled: true,
      fillColor: theme.colorScheme.surfaceContainer,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: theme.textTheme.bodyMedium!.copyWith(
        color: theme.colorScheme.onSurface.withAlpha(200),
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(
          color: theme.colorScheme.surfaceContainerHigh,
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
      ),
    );
  }
}

class _DraggableBrowserTab extends StatelessWidget {
  final int tabId;
  final bool selected;
  final int initialWindowId;
  final VoidCallback onSelected;
  final VoidCallback onClose;
  final void Function(_DraggedTabData dragData, DragUpdateDetails details)
  onDragUpdate;

  const _DraggableBrowserTab({
    required this.tabId,
    required this.selected,
    required this.initialWindowId,
    required this.onSelected,
    required this.onClose,
    required this.onDragUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final dragData = _DraggedTabData(
      tabId: tabId,
      currentWindowId: initialWindowId,
    );

    final tab = BrowserTab(
      viewId: tabId,
      selected: selected,
      onTabSelected: onSelected,
      onTabClosed: onClose,
    );

    return Draggable<_DraggedTabData>(
      data: dragData,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Opacity(opacity: 0.92, child: tab),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tab),
      onDragUpdate: (details) => onDragUpdate(dragData, details),
      child: tab,
    );
  }
}

class _TabDropTarget extends StatelessWidget {
  final int windowId;
  final int targetTabId;
  final void Function(_DraggedTabData dragData) onReorderAccepted;
  final Widget child;

  const _TabDropTarget({
    required this.windowId,
    required this.targetTabId,
    required this.onReorderAccepted,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DraggedTabData>(
      onWillAcceptWithDetails: (details) {
        return details.data.currentWindowId == windowId &&
            details.data.tabId != targetTabId;
      },
      onAcceptWithDetails: (details) {
        onReorderAccepted(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: EdgeInsets.only(left: isHovering ? 2 : 0),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isHovering
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class _TabEndDropTarget extends StatelessWidget {
  final int windowId;
  final void Function(_DraggedTabData dragData) onReorderAccepted;

  const _TabEndDropTarget({
    required this.windowId,
    required this.onReorderAccepted,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<_DraggedTabData>(
      onWillAcceptWithDetails: (details) {
        return details.data.currentWindowId == windowId;
      },
      onAcceptWithDetails: (details) {
        onReorderAccepted(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: candidateData.isNotEmpty ? 20 : 12,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: candidateData.isNotEmpty
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DraggedTabData {
  final int tabId;
  int currentWindowId;

  _DraggedTabData({required this.tabId, required this.currentWindowId});
}

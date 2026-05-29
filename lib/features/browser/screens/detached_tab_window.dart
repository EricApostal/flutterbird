import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/tab.dart';
import 'package:flutterbird/features/browser/components/omnibox_bar.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/detached_browser_window_session.dart';
import 'package:ladybird/ladybird.dart';

class DetachedTabWindowScreen extends StatefulWidget {
  final DetachedBrowserWindowSession session;

  const DetachedTabWindowScreen({super.key, required this.session});

  @override
  State<DetachedTabWindowScreen> createState() =>
      _DetachedTabWindowScreenState();
}

class _DetachedTabWindowScreenState extends State<DetachedTabWindowScreen> {
  static const double _kDetachDragThreshold = 18;

  final GlobalKey _tabStripViewportKey = GlobalKey();
  int? _draggingViewId;
  bool _isDetachingDraggedTab = false;
  int? _detachedDuringCurrentDragViewId;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_handleSessionChanged);
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
  }

  @override
  void didUpdateWidget(covariant DetachedTabWindowScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    oldWidget.session.removeListener(_handleSessionChanged);
    widget.session.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    widget.session.removeListener(_handleSessionChanged);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    super.dispose();
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (_draggingViewId == null) return;
    if (event is PointerMoveEvent || event is PointerHoverEvent) {
      _maybeDetachDraggedTab(event.position);
    }
  }

  void _handleTabReorderStart(int index) {
    final tabs = widget.session.tabs;
    if (index < 0 || index >= tabs.length) {
      _draggingViewId = null;
      return;
    }
    _detachedDuringCurrentDragViewId = null;
    _draggingViewId = tabs[index].viewId;
  }

  void _handleTabReorderEnd() {
    _draggingViewId = null;
    _isDetachingDraggedTab = false;
    _detachedDuringCurrentDragViewId = null;
  }

  Rect? _tabStripViewportRect() {
    final renderObject = _tabStripViewportKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  void _maybeDetachDraggedTab(Offset pointerPosition) {
    if (!Platform.isLinux) return;
    if (_isDetachingDraggedTab) return;

    final draggingViewId = _draggingViewId;
    if (draggingViewId == null) return;

    final tabs = widget.session.tabs;
    if (tabs.length <= 1) return;
    if (!tabs.any((tab) => tab.viewId == draggingViewId)) {
      _draggingViewId = null;
      return;
    }

    final tabStripRect = _tabStripViewportRect();
    if (tabStripRect == null) return;

    final draggedOutsideVertically =
        pointerPosition.dy < tabStripRect.top - _kDetachDragThreshold ||
        pointerPosition.dy > tabStripRect.bottom + _kDetachDragThreshold;
    if (!draggedOutsideVertically) return;

    _isDetachingDraggedTab = true;
    _detachedDuringCurrentDragViewId = draggingViewId;
    _draggingViewId = null;

    unawaited(
      BrowserTabActions.detachTabFromDetachedSessionToNewWindow(
        context,
        sourceSession: widget.session,
        detachViewId: draggingViewId,
        initialPointerPosition: pointerPosition,
        continueDragAfterDetach: true,
      ).whenComplete(() {
        if (!mounted) return;
        _isDetachingDraggedTab = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTab = widget.session.currentTab;
    if (currentTab == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          _DetachedWindowTabStrip(
            key: _tabStripViewportKey,
            session: widget.session,
            onTabReorderStart: _handleTabReorderStart,
            onTabReorderEnd: _handleTabReorderEnd,
            detachedDuringCurrentDrag: _detachedDuringCurrentDragViewId != null,
          ),
          BrowserOmniboxBar(currentTabController: currentTab),
          Expanded(child: LadybirdView(controller: currentTab)),
        ],
      ),
    );
  }
}

class _DetachedWindowTabStrip extends StatelessWidget {
  const _DetachedWindowTabStrip({
    super.key,
    required this.session,
    required this.onTabReorderStart,
    required this.onTabReorderEnd,
    required this.detachedDuringCurrentDrag,
  });

  final DetachedBrowserWindowSession session;
  final ValueChanged<int> onTabReorderStart;
  final VoidCallback onTabReorderEnd;
  final bool detachedDuringCurrentDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = session.tabs;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outline.withAlpha(36)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 2),
              buildDefaultDragHandles: false,
              itemCount: tabs.length,
              onReorderStart: onTabReorderStart,
              onReorderEnd: (_) => onTabReorderEnd(),
              proxyDecorator:
                  (Widget child, int index, Animation<double> animation) {
                    return Material(
                      color: Colors.transparent,
                      elevation: 0,
                      child: child,
                    );
                  },
              onReorder: (oldIndex, newIndex) {
                if (detachedDuringCurrentDrag) return;
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                final maxIndex = tabs.length - 1;
                if (newIndex > maxIndex) {
                  newIndex = maxIndex;
                }
                if (newIndex < 0 || oldIndex == newIndex) return;
                session.reorderTabs(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final dragEnabled = tabs.length > 1;
                return ReorderableDragStartListener(
                  key: ValueKey(tab.viewId),
                  index: index,
                  enabled: dragEnabled,
                  child: SizedBox(
                    width: 220,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: dragEnabled
                          ? null
                          : (details) {
                              BrowserTabActions.startWindowDragFromTab(
                                context,
                                globalPointerPosition: details.globalPosition,
                              );
                            },
                      child: BrowserTab(
                        viewId: tab.viewId,
                        selected: tab.viewId == session.currentViewId,
                        controllerOverride: tab,
                        onTabSelected: () => session.selectTab(tab.viewId),
                        onTabClosed: () => session.closeTab(tab.viewId),
                        minWidth: 220,
                        width: 220,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 34,
            child: IconButton(
              iconSize: 18,
              splashRadius: 16,
              tooltip: 'New tab',
              icon: const Icon(Icons.add),
              onPressed: session.addTab,
            ),
          ),
        ],
      ),
    );
  }
}

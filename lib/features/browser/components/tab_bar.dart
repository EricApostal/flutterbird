import 'dart:io';
import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/omnibox_bar.dart';
import 'package:flutterbird/features/browser/components/tab.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';
import 'package:window_manager/window_manager.dart';

class BrowserTabBar extends ConsumerStatefulWidget {
  final int currentViewId;

  const BrowserTabBar({required this.currentViewId, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BrowserTabBarState();
}

class _BrowserTabBarState extends ConsumerState<BrowserTabBar>
    with WindowListener {
  static const double _kMacControlsWidth = 78;
  static const double _kWindowsControlsWidth = 138;
  static const double _kMinTabWidth = 170;
  static const double _kMaxTabWidth = 225;
  static const double _kAddButtonWidth = 48;

  bool _isWindowMaximized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      windowManager.addListener(this);
      _refreshWindowState();
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _refreshWindowState() async {
    final isMaximized = await windowManager.isMaximized();
    if (!mounted || isMaximized == _isWindowMaximized) return;
    setState(() {
      _isWindowMaximized = isMaximized;
    });
  }

  @override
  void onWindowMaximize() => _refreshWindowState();

  @override
  void onWindowUnmaximize() => _refreshWindowState();

  @override
  void onWindowRestore() => _refreshWindowState();

  void _openNewTab(BuildContext context) {
    final controller = ref.read(browserTabControllerProvider.notifier).add();
    context.go('/browser/tab/${controller.viewId}');
  }

  void _closeTab(
    BuildContext context,
    int viewId,
    List<LadybirdController> tabs,
  ) {
    final index = tabs.indexWhere((tab) => tab.viewId == viewId);
    if (index < 0) return;

    if (viewId == widget.currentViewId) {
      if (tabs.length == 1) {
        exit(0);
      }
      if (index == 0) {
        context.go('/browser/tab/${tabs[1].viewId}');
      } else {
        context.go('/browser/tab/${tabs[index - 1].viewId}');
      }
    }

    ref.read(browserTabControllerProvider.notifier).remove(viewId);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabControllerProvider);
    final currentTabController = ref.watch(
      browserTabProvider(widget.currentViewId),
    );

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    final leadingControlsPadding = Platform.isMacOS ? _kMacControlsWidth : 8.0;
    final trailingControlsPadding = Platform.isWindows
        ? _kWindowsControlsWidth
        : 8.0;

    return Column(
      children: [
        SizedBox(
          height: 45,
          child: Row(
            children: [
              DragToMoveArea(
                child: SizedBox(
                  height: double.infinity,
                  width: leadingControlsPadding,
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tabCount = tabs.isEmpty ? 1 : tabs.length;
                    final pinAddButton =
                        (tabs.length * _kMinTabWidth) + _kAddButtonWidth >
                        constraints.maxWidth - trailingControlsPadding;
                    final availableForTabViewport = math.max(
                      0.0,
                      constraints.maxWidth -
                          trailingControlsPadding -
                          (pinAddButton ? _kAddButtonWidth : 0.0),
                    );
                    final adaptiveTabWidth = math.min(
                      _kMaxTabWidth,
                      math.max(
                        _kMinTabWidth,
                        availableForTabViewport / tabCount,
                      ),
                    );
                    final tabContentWidth =
                        (adaptiveTabWidth * tabs.length) +
                        (pinAddButton ? 0 : _kAddButtonWidth);
                    final tabViewportWidth = math.min(
                      availableForTabViewport,
                      tabContentWidth,
                    );
                    final dragAreaWidth = math.max(
                      trailingControlsPadding,
                      constraints.maxWidth -
                          tabViewportWidth -
                          (pinAddButton ? _kAddButtonWidth : 0.0),
                    );

                    Widget buildTabList({required bool includeAddButton}) {
                      return ReorderableListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, index) {
                          if (includeAddButton && index == tabs.length) {
                            return ReorderableDragStartListener(
                              key: const ValueKey('add'),
                              index: index,
                              enabled: false,
                              child: SizedBox(
                                width: _kAddButtonWidth,
                                child: IconButton(
                                  icon: const Icon(Icons.add, size: 20),
                                  onPressed: () => _openNewTab(context),
                                ),
                              ),
                            );
                          }

                          final id = tabs[index].viewId;
                          return ReorderableDragStartListener(
                            key: ValueKey(id),
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: BrowserTab(
                                viewId: tabs[index].viewId,
                                selected: id == widget.currentViewId,
                                minWidth: _kMinTabWidth,
                                width: adaptiveTabWidth,
                                onTabClosed: () {
                                  HapticFeedback.lightImpact();
                                  _closeTab(context, id, tabs);
                                },
                              ),
                            ),
                          );
                        },
                        proxyDecorator:
                            (
                              Widget child,
                              int index,
                              Animation<double> animation,
                            ) {
                              return Material(
                                color: Colors.transparent,
                                elevation: 0,
                                child: child,
                              );
                            },
                        itemCount: tabs.length + (includeAddButton ? 1 : 0),
                        onReorder: (oldIndex, newIndex) {
                          if (includeAddButton && oldIndex == tabs.length) {
                            return;
                          }
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final maxIndex = tabs.length - 1;
                          if (newIndex > maxIndex) {
                            newIndex = maxIndex;
                          }
                          if (newIndex < 0 || oldIndex == newIndex) return;
                          ref
                              .read(browserTabControllerProvider.notifier)
                              .reorder(oldIndex, newIndex);
                        },
                      );
                    }

                    return Row(
                      children: [
                        SizedBox(
                          width: tabViewportWidth,
                          child: buildTabList(includeAddButton: !pinAddButton),
                        ),
                        if (pinAddButton)
                          SizedBox(
                            width: _kAddButtonWidth,
                            child: IconButton(
                              icon: const Icon(Icons.add, size: 20),
                              onPressed: () => _openNewTab(context),
                            ),
                          ),
                        SizedBox(
                          width: dragAreaWidth,
                          child: DragToMoveArea(
                            child: SizedBox(
                              height: double.infinity,
                              width: double.infinity,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        BrowserOmniboxBar(currentTabController: currentTabController),
      ],
    );
  }
}

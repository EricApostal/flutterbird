import 'dart:io';
import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/omnibox_bar.dart';
import 'package:flutterbird/features/browser/components/tab.dart';
import 'package:flutterbird/features/frontend/abstraction/frontend_layer.dart';
import 'package:flutterbird/features/frontend/components/adaptive_widgets.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_layout_mode.dart';
import 'package:window_manager/window_manager.dart';

class BrowserTabAnimationConfig {
  final Duration sizeDuration;
  final Curve sizeCurve;

  const BrowserTabAnimationConfig({
    this.sizeDuration = const Duration(milliseconds: 180),
    this.sizeCurve = Curves.easeOutCubic,
  });
}

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
  static const double _kLayoutToggleButtonWidth = 40;
  static const BrowserTabAnimationConfig _kTabAnimationConfig =
      BrowserTabAnimationConfig();

  bool _isWindowMaximized = false;
  bool _animateNewTabs = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _animateNewTabs = true;
      });
    });

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

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    final isFluent = frontend.flavor == FrontendFlavor.fluent;
    final tabStripHeight = isFluent ? 40.0 : 45.0;
    final tabListPadding = isFluent
        ? const EdgeInsets.only(top: 2)
        : const EdgeInsets.only(top: 4, bottom: 4);

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
          height: tabStripHeight,
          child: Row(
            children: [
              DragToMoveArea(
                child: SizedBox(
                  height: double.infinity,
                  width: leadingControlsPadding,
                ),
              ),
              SizedBox(
                width: _kLayoutToggleButtonWidth,
                child: FrontendIconButton(
                  icon: const Icon(Icons.dashboard),
                  tooltip: 'Switch to vertical tabs',
                  onPressed: () {
                    ref
                        .read(browserTabLayoutModeControllerProvider.notifier)
                        .setVertical();
                  },
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final tabCount = tabs.isEmpty ? 1 : tabs.length;
                    final pinAddButton =
                        (tabs.length * _kMinTabWidth) + _kAddButtonWidth >
                        constraints.maxWidth -
                            trailingControlsPadding -
                            _kLayoutToggleButtonWidth;
                    final availableForTabViewport = math.max(
                      0.0,
                      constraints.maxWidth -
                          trailingControlsPadding -
                          _kLayoutToggleButtonWidth -
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
                          _kLayoutToggleButtonWidth -
                          (pinAddButton ? _kAddButtonWidth : 0.0),
                    );

                    Widget buildTabList({required bool includeAddButton}) {
                      return ReorderableListView.builder(
                        shrinkWrap: true,
                        padding: tabListPadding,
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        itemBuilder: (context, index) {
                          if (includeAddButton && index == tabs.length) {
                            return ReorderableDragStartListener(
                              key: const ValueKey('add'),
                              index: index,
                              enabled: false,
                              child: FrontendIconButton(
                                icon: const Icon(Icons.add, size: 20),
                                onPressed: () =>
                                    BrowserTabActions.openNewTab(ref, context),
                              ),
                            );
                          }

                          final id = tabs[index].viewId;
                          return _AnimatedBrowserTabItem(
                            key: ValueKey(id),
                            index: index,
                            viewId: tabs[index].viewId,
                            selected: id == widget.currentViewId,
                            minWidth: _kMinTabWidth,
                            width: adaptiveTabWidth,
                            animateOnMount: _animateNewTabs,
                            animationConfig: _kTabAnimationConfig,
                            onCloseRequested: () {
                              HapticFeedback.lightImpact();
                              return BrowserTabActions.prepareCloseTabNavigation(
                                context,
                                currentViewId: widget.currentViewId,
                                closeViewId: id,
                                tabs: tabs,
                              );
                            },
                            onCloseCommitted: () =>
                                BrowserTabActions.commitCloseTab(ref, id),
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
                            // width: _kAddButtonWidth,
                            child: FrontendIconButton(
                              icon: const Icon(Icons.add, size: 20),
                              onPressed: () =>
                                  BrowserTabActions.openNewTab(ref, context),
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

class _AnimatedBrowserTabItem extends StatefulWidget {
  final int index;
  final int viewId;
  final bool selected;
  final double minWidth;
  final double width;
  final bool animateOnMount;
  final BrowserTabAnimationConfig animationConfig;
  final bool Function() onCloseRequested;
  final VoidCallback onCloseCommitted;

  const _AnimatedBrowserTabItem({
    super.key,
    required this.index,
    required this.viewId,
    required this.selected,
    required this.minWidth,
    required this.width,
    required this.animateOnMount,
    required this.animationConfig,
    required this.onCloseRequested,
    required this.onCloseCommitted,
  });

  @override
  State<_AnimatedBrowserTabItem> createState() =>
      _AnimatedBrowserTabItemState();
}

class _AnimatedBrowserTabItemState extends State<_AnimatedBrowserTabItem> {
  late bool _isExpanded;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = !widget.animateOnMount;

    if (widget.animateOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _isClosing || _isExpanded) return;
        setState(() {
          _isExpanded = true;
        });
      });
    }
  }

  Future<void> _handleClose() async {
    if (_isClosing) return;
    if (!widget.onCloseRequested()) return;

    setState(() {
      _isClosing = true;
      _isExpanded = false;
    });

    await Future<void>.delayed(widget.animationConfig.sizeDuration);
    if (!mounted) return;
    widget.onCloseCommitted();
  }

  @override
  Widget build(BuildContext context) {
    final frontend = FrontendScope.of(context);
    final useDelayedDragStart = frontend.flavor == FrontendFlavor.fluent;

    final tabChild = ClipRect(
      child: AnimatedContainer(
        duration: widget.animationConfig.sizeDuration,
        curve: widget.animationConfig.sizeCurve,
        width: _isExpanded ? widget.width + 2 : 0,
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: SizedBox(
            width: widget.width,
            child: IgnorePointer(
              ignoring: _isClosing || !_isExpanded,
              child: BrowserTab(
                viewId: widget.viewId,
                selected: widget.selected,
                minWidth: widget.minWidth,
                width: widget.width,
                onTabClosed: _handleClose,
              ),
            ),
          ),
        ),
      ),
    );

    if (useDelayedDragStart) {
      return ReorderableDelayedDragStartListener(
        index: widget.index,
        enabled: _isExpanded && !_isClosing,
        child: tabChild,
      );
    }

    return ReorderableDragStartListener(
      index: widget.index,
      enabled: _isExpanded && !_isClosing,
      child: tabChild,
    );
  }
}

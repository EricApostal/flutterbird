import 'dart:io';
import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_bar.dart';
import 'package:flutterbird/features/browser/components/desktop/tabs/tab.dart';
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

  // Which tab rows are expanded, and which ones are collapsing on their way
  // out. Kept by view id rather than inside the row: the reorderable list
  // builds its items under a `_ReorderableItemGlobalKey` that includes the
  // item's index, so a reorder rebuilds the moved row and everything after it,
  // which would reset a flag stored in the row (and make the row animate in
  // again, since a rebuilt `AnimatedContainer` does not animate from its
  // previous height). Held here, a reorder leaves it untouched.
  final Set<int> _expandedViewIds = <int>{};
  final Set<int> _closingViewIds = <int>{};

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

  /// Brings [_expandedViewIds]/[_closingViewIds] in line with the open tabs:
  /// gone rows are dropped, rows already accounted for are left alone (so a
  /// reorder never touches this), and a tab seen for the first time is expanded
  /// immediately when it predates the first frame or one frame later when it
  /// was opened afterwards, keeping the open animation new tabs had before.
  void _syncRowExpandState(Iterable<int> viewIds) {
    final present = viewIds.toSet();
    _expandedViewIds.removeWhere((id) => !present.contains(id));
    _closingViewIds.removeWhere((id) => !present.contains(id));

    final toExpand = <int>[];
    for (final id in present) {
      if (_expandedViewIds.contains(id) || _closingViewIds.contains(id)) {
        continue;
      }
      if (!_animateNewTabs) {
        _expandedViewIds.add(id);
      } else {
        toExpand.add(id);
      }
    }

    if (toExpand.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _expandedViewIds.addAll(toExpand);
      });
    });
  }

  /// Collapses [viewId]'s row first and closes the tab once that animation has
  /// run, so closing animates instead of the row vanishing mid-frame.
  Future<void> _closeTab(int viewId) async {
    if (_closingViewIds.contains(viewId)) return;

    HapticFeedback.lightImpact();
    final canClose = BrowserTabActions.prepareCloseTabNavigation(
      context,
      currentViewId: widget.currentViewId,
      closeViewId: viewId,
      tabs: ref.read(browserTabControllerProvider),
    );
    if (!canClose) return;

    setState(() {
      _closingViewIds.add(viewId);
      _expandedViewIds.remove(viewId);
    });

    await Future<void>.delayed(_kTabAnimationConfig.sizeDuration);
    if (!mounted) return;
    BrowserTabActions.commitCloseTab(ref, viewId);
  }

  @override
  Widget build(BuildContext context) {
    final tabStripHeight = 40.0;
    final tabListPadding = const EdgeInsets.only(top: 4, bottom: 4);

    final tabs = ref.watch(browserTabControllerProvider);
    _syncRowExpandState(tabs.map((tab) => tab.viewId));
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
              if (!Platform.isAndroid)
                DragToMoveArea(
                  child: SizedBox(
                    height: double.infinity,
                    width: leadingControlsPadding,
                  ),
                ),
              SizedBox(
                width: _kLayoutToggleButtonWidth,
                child: IconButton(
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
                    // The leading window-button area and the layout toggle sit
                    // in the strip's Row *before* this builder, so `maxWidth`
                    // already excludes them; the only inset left to honour is
                    // the trailing window-button reservation. Strip content has
                    // to stop exactly at that boundary — the tab viewport (and
                    // with it the point where scrolled tabs get clipped) running
                    // 40px short of it left a dead band on the right that the
                    // scrolled tabs disappeared behind.
                    final contentWidth = math.max(
                      0.0,
                      constraints.maxWidth - trailingControlsPadding,
                    );
                    final pinAddButton =
                        (tabs.length * _kMinTabWidth) + _kAddButtonWidth >
                        contentWidth;
                    final availableForTabViewport = math.max(
                      0.0,
                      contentWidth - (pinAddButton ? _kAddButtonWidth : 0.0),
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
                    double tabViewportWidth = math.min(
                      availableForTabViewport,
                      tabContentWidth,
                    );

                    // Everything the tabs do not use is window-drag surface,
                    // never less than the trailing reservation itself.
                    final dragAreaWidth = math.max(
                      trailingControlsPadding,
                      constraints.maxWidth -
                          tabViewportWidth -
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
                              child: IconButton(
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
                            expanded: _expandedViewIds.contains(id),
                            minWidth: _kMinTabWidth,
                            width: adaptiveTabWidth,
                            animationConfig: _kTabAnimationConfig,
                            onTabClosed: () => _closeTab(id),
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
                            child: IconButton(
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

/// One tab of the horizontal strip.
///
/// Like the sidebar's rows, this holds no state of its own: [expanded] comes
/// from the bar, so reordering the strip (which rebuilds items positionally)
/// cannot reset a tab's animation — see
/// [_BrowserTabBarState._expandedViewIds].
class _AnimatedBrowserTabItem extends StatelessWidget {
  final int index;
  final int viewId;
  final bool selected;
  final double minWidth;
  final double width;

  /// Whether the tab is expanded. A tab that is not expanded is either still
  /// animating in or on its way out.
  final bool expanded;
  final BrowserTabAnimationConfig animationConfig;
  final VoidCallback onTabClosed;

  const _AnimatedBrowserTabItem({
    super.key,
    required this.index,
    required this.viewId,
    required this.selected,
    required this.minWidth,
    required this.width,
    required this.expanded,
    required this.animationConfig,
    required this.onTabClosed,
  });

  @override
  Widget build(BuildContext context) {
    final tabChild = ClipRect(
      child: AnimatedContainer(
        duration: animationConfig.sizeDuration,
        curve: animationConfig.sizeCurve,
        width: expanded ? width + 2 : 0,
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: SizedBox(
            width: width,
            child: IgnorePointer(
              ignoring: !expanded,
              child: BrowserTab(
                viewId: viewId,
                selected: selected,
                minWidth: minWidth,
                width: width,
                onTabClosed: onTabClosed,
              ),
            ),
          ),
        ),
      ),
    );

    return ReorderableDragStartListener(
      index: index,
      enabled: expanded,
      child: tabChild,
    );
  }
}

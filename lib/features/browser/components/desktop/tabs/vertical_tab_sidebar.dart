import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:flutterbird/features/browser/components/desktop/tabs/tab.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_layout_mode.dart';
import 'package:window_manager/window_manager.dart';

const Duration _kSidebarTabAnimationDuration = Duration(milliseconds: 180);
const Curve _kSidebarTabAnimationCurve = Curves.easeOutCubic;

class BrowserVerticalTabSidebar extends ConsumerStatefulWidget {
  static const double sidebarWidth = 272;

  final int currentViewId;

  const BrowserVerticalTabSidebar({super.key, required this.currentViewId});

  @override
  ConsumerState<BrowserVerticalTabSidebar> createState() =>
      _BrowserVerticalTabSidebarState();
}

class _BrowserVerticalTabSidebarState
    extends ConsumerState<BrowserVerticalTabSidebar>
    with WindowListener {
  static const double _kSidebarWidth = BrowserVerticalTabSidebar.sidebarWidth;
  static const double _kTabHeight = 36;
  static const double _kMacControlsWidth = 78;

  bool _animateNewTabs = false;

  // Which rows are expanded, and which ones are collapsing on their way out.
  //
  // This lives here rather than inside the row itself on purpose: the
  // reorderable list builds every item under a `_ReorderableItemGlobalKey`
  // that mixes the item's key with its *index*, so reordering rebuilds the
  // moved row and all the rows below it from scratch. An expand flag held
  // inside the row would be reset with that rebuild — and since a rebuilt
  // `AnimatedContainer` starts at its target height without animating, a
  // fresh row animates in again whenever the list is reordered. Keyed by view
  // id (never by position), the rows below keep their height through the
  // reorder and the state of the list cannot be scrambled by it.
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
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  /// Brings [_expandedViewIds]/[_closingViewIds] in line with the open tabs.
  ///
  /// Rows that are gone are dropped; rows that are already accounted for are
  /// left alone, so reordering the list does not touch this state at all. A
  /// tab that shows up here for the first time is expanded right away when it
  /// has been there since the first frame, and one frame later otherwise, so
  /// tabs opening after startup animate in exactly as they did before this
  /// state moved out of the row.
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

    await Future<void>.delayed(_kSidebarTabAnimationDuration);
    if (!mounted) return;
    BrowserTabActions.commitCloseTab(ref, viewId);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabControllerProvider);
    _syncRowExpandState(tabs.map((tab) => tab.viewId));
    final theme = Theme.of(context);
    final padding = MediaQuery.paddingOf(context);

    return Container(
      width: _kSidebarWidth,
      decoration: BoxDecoration(
        color: omniboxSurfaceColor(theme),
        border: Border(
          right: BorderSide(color: theme.colorScheme.outline.withAlpha(36)),
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: padding.top),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(width: Platform.isMacOS ? _kMacControlsWidth : 8),
                Expanded(
                  child: DragToMoveArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.splitscreen_outlined, size: 18),
                  tooltip: 'Switch to horizontal tabs',
                  onPressed: () {
                    ref
                        .read(browserTabLayoutModeControllerProvider.notifier)
                        .setHorizontal();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  sliver: SliverReorderableList(
                    itemCount: tabs.length,
                    proxyDecorator:
                        (Widget child, int index, Animation<double> animation) {
                          return Material(
                            color: Colors.transparent,
                            elevation: 0,
                            child: child,
                          );
                        },
                    itemBuilder: (context, index) {
                      final id = tabs[index].viewId;
                      return _AnimatedSidebarTabItem(
                        key: ValueKey(id),
                        index: index,
                        viewId: id,
                        selected: id == widget.currentViewId,
                        expanded: _expandedViewIds.contains(id),
                        width: _kSidebarWidth - 16,
                        height: _kTabHeight,
                        onTabClosed: () => _closeTab(id),
                      );
                    },
                    onReorder: (oldIndex, newIndex) {
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
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  sliver: SliverToBoxAdapter(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8.0),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          BrowserTabActions.openNewTab(ref, context);
                        },
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 36),
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              Colors.black,
                              theme.colorScheme.primaryContainer,
                              0.5,
                            )!,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 10,
                                      right: 6,
                                    ),
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8.0,
                                          ),
                                          child: Icon(
                                            Icons.add,
                                            size: 16,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            'New Tab',
                                            style: TextStyle(
                                              color:
                                                  theme.colorScheme.onSurface,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the sidebar's tab list.
///
/// The row owns no state: whether it is expanded (and therefore how tall it
/// is) comes from the sidebar itself, because the reorderable list rebuilds
/// items positionally and would otherwise reset it — see
/// [_BrowserVerticalTabSidebarState._expandedViewIds].
class _AnimatedSidebarTabItem extends StatelessWidget {
  final int index;
  final int viewId;
  final bool selected;

  /// Whether the row is expanded. A row that is not expanded is either still
  /// animating in or on its way out.
  final bool expanded;
  final double width;
  final double height;
  final VoidCallback onTabClosed;

  const _AnimatedSidebarTabItem({
    super.key,
    required this.index,
    required this.viewId,
    required this.selected,
    required this.expanded,
    required this.width,
    required this.height,
    required this.onTabClosed,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      enabled: expanded,
      child: ClipRect(
        child: AnimatedContainer(
          duration: _kSidebarTabAnimationDuration,
          curve: _kSidebarTabAnimationCurve,
          height: expanded ? height + 6 : 0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              height: height,
              width: width,
              child: IgnorePointer(
                ignoring: !expanded,
                child: BrowserTab(
                  viewId: viewId,
                  selected: selected,
                  variant: BrowserTabVariant.arcSidebar,
                  minWidth: width,
                  width: width,
                  minHeight: height,
                  onTabClosed: onTabClosed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

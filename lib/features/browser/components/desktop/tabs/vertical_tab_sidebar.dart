import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/browser/components/desktop/tabs/tab.dart';
import 'package:rubisco_browser/features/browser/components/desktop/tabs/tab_strip.dart';
import 'package:rubisco_browser/features/browser/state/tab_actions.dart';
import 'package:rubisco_browser/features/browser/state/fullscreen_mode.dart';
import 'package:rubisco_browser/features/browser/state/tab_layout_mode.dart';
import 'package:rubisco_browser/features/windows/tab_drag_controller.dart';
import 'package:rubisco_browser/features/windows/window_drag_area.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';

class BrowserVerticalTabSidebar extends ConsumerStatefulWidget {
  static const double sidebarWidth = 272;

  final int currentViewId;

  const BrowserVerticalTabSidebar({super.key, required this.currentViewId});

  @override
  ConsumerState<BrowserVerticalTabSidebar> createState() =>
      _BrowserVerticalTabSidebarState();
}

class _BrowserVerticalTabSidebarState
    extends ConsumerState<BrowserVerticalTabSidebar> {
  static const double _kSidebarWidth = BrowserVerticalTabSidebar.sidebarWidth;
  static const double _kSidebarPadding = 8;
  static const double _kTabHeight = 36;
  static const double _kTabSpacing = 3;
  static const double _kTabSlot = _kTabHeight + _kTabSpacing;
  static const double _kNewTabExtent = _kTabHeight + 8;
  static const double _kMacControlsWidth = 78;

  final ScrollController _scrollController = ScrollController();
  // Where a dragged tab can be let go, and where the first tab starts.
  final GlobalKey _sidebarKey = GlobalKey();
  final GlobalKey _tabsKey = GlobalKey();

  int? _registeredWindowId;
  VoidCallback? _unregisterStrip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final windowId = BrowserWindowScope.of(context);
    if (windowId == _registeredWindowId) return;
    _unregisterStrip?.call();
    _registeredWindowId = windowId;
    _unregisterStrip = ref
        .read(tabDragControllerProvider)
        .registerStrip(windowId, _report);
  }

  @override
  void dispose() {
    _unregisterStrip?.call();
    _scrollController.dispose();
    super.dispose();
  }

  // The sidebar is built while the tabs are along the top too, only closed.
  TabStripReport? _report() {
    final windowId = _registeredWindowId;
    if (windowId == null ||
        ref.read(browserTabLayoutModeControllerProvider) !=
            BrowserTabLayoutMode.vertical ||
        ref.read(browserFullscreenModeControllerProvider(windowId))) {
      return null;
    }
    final sidebar = _sidebarKey.currentContext?.findRenderObject();
    final tabs = _tabsKey.currentContext?.findRenderObject();
    if (sidebar is! RenderBox || tabs is! RenderBox) return null;
    if (!sidebar.attached || !sidebar.hasSize || !tabs.hasSize) return null;

    return TabStripReport(
      bounds: sidebar.localToGlobal(Offset.zero) & sidebar.size,
      tabsOrigin: tabs.localToGlobal(Offset.zero),
      axis: Axis.vertical,
      slotExtentFor: (_) => _kTabSlot,
      scrollOffset: _scrollController.hasClients ? _scrollController.offset : 0,
    );
  }

  /// Closes [viewId]'s tab. Its row collapses first and the tab goes away once
  /// that has run; see [closingTabsProvider], which every close path shares.
  void _closeTab(int viewId) {
    HapticFeedback.lightImpact();
    BrowserTabActions.closeTab(
      context,
      currentViewId: widget.currentViewId,
      closeViewId: viewId,
    );
  }

  Widget _buildNewTabButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
      child: BirdPressable(
        onPressed: () {
          HapticFeedback.lightImpact();
          BrowserTabActions.openNewTab(ref, context);
        },
        builder: (context, state) => BirdFocusRing(
          visible: state.focused,
          child: Container(
            decoration: BoxDecoration(
              color: state.pressed
                  ? context.bird.pressed
                  : (state.hovered ? context.bird.hover : null),
              borderRadius: BorderRadius.circular(BirdRadius.control),
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                const BirdIcon(BirdGlyph.plus, size: 14),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'New Tab',
                    style: context.birdText(size: BirdTextSize.small),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final windowId = BrowserWindowScope.of(context);
    final tabIds =
        ref.watch(browserWindowProvider(windowId))?.tabIds ?? const <int>[];
    final closingViewIds = ref.watch(closingTabsProvider);
    final colors = context.bird;
    final padding = MediaQuery.paddingOf(context);

    return Container(
      key: _sidebarKey,
      width: _kSidebarWidth,
      decoration: BoxDecoration(
        color: colors.frame,
        border: Border(right: BorderSide(color: colors.toolbarBorder)),
      ),
      child: Column(
        children: [
          SizedBox(height: padding.top),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(width: Platform.isMacOS ? _kMacControlsWidth : 8),
                const Expanded(
                  child: WindowDragArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
                BirdToolbarButton(
                  glyph: BirdGlyph.tabs,
                  tooltip: 'Switch to horizontal tabs',
                  size: 30,
                  onPressed: () {
                    ref
                        .read(browserTabLayoutModeControllerProvider.notifier)
                        .setHorizontal();
                  },
                ),
                const SizedBox(width: _kSidebarPadding),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kSidebarPadding),
              child: Align(
                alignment: Alignment.topCenter,
                child: KeyedSubtree(
                  key: _tabsKey,
                  child: TabStrip(
                    windowId: windowId,
                    axis: Axis.vertical,
                    tabIds: tabIds,
                    closingTabIds: closingViewIds,
                    slotExtent: _kTabSlot,
                    crossExtent: _kSidebarWidth - _kSidebarPadding * 2,
                    spacing: _kTabSpacing,
                    scrollController: _scrollController,
                    trailing: _buildNewTabButton(),
                    trailingExtent: _kNewTabExtent,
                    itemBuilder: (context, id) => BrowserTab(
                      viewId: id,
                      selected: id == widget.currentViewId,
                      variant: BrowserTabVariant.arcSidebar,
                      minWidth: _kSidebarWidth - _kSidebarPadding * 2,
                      width: _kSidebarWidth - _kSidebarPadding * 2,
                      minHeight: _kTabHeight,
                      onTabClosed: () => _closeTab(id),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_bar.dart';
import 'package:rubisco_browser/features/browser/components/desktop/tabs/tab.dart';
import 'package:rubisco_browser/features/browser/components/desktop/tabs/tab_strip.dart';
import 'package:rubisco_browser/features/browser/state/tab_actions.dart';
import 'package:rubisco_browser/features/browser/state/tab_layout_mode.dart';
import 'package:rubisco_browser/features/windows/tab_drag_controller.dart';
import 'package:rubisco_browser/features/windows/window_drag_area.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';

class BrowserTabBar extends ConsumerStatefulWidget {
  final int currentViewId;

  const BrowserTabBar({required this.currentViewId, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BrowserTabBarState();
}

class _BrowserTabBarState extends ConsumerState<BrowserTabBar> {
  static const double _kMacControlsWidth = 78;
  static const double _kWindowsControlsWidth = 138;
  static const double _kMinTabWidth = 170;
  static const double _kMaxTabWidth = 225;
  static const double _kTabSpacing = 2;
  static const double _kAddButtonWidth = 40;
  static const double _kLayoutToggleButtonWidth = 36;
  static const double _kStripHeight = 40;
  static const double _kStripPadding = 4;

  final ScrollController _scrollController = ScrollController();
  // Where a dragged tab can be let go, and where the first tab starts.
  final GlobalKey _stripKey = GlobalKey();
  final GlobalKey _tabsKey = GlobalKey();

  // The room the tabs and the add button have, from the last layout.
  double _contentWidth = 0;

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

  /// Whether [tabCount] tabs are too many for the add button to follow them,
  /// which pins it to the end of the strip.
  bool _pinsAddButton(int tabCount) =>
      tabCount * (_kMinTabWidth + _kTabSpacing) + _kAddButtonWidth >
      _contentWidth;

  double _viewportFor(int tabCount) => math.max(
    0.0,
    _contentWidth - (_pinsAddButton(tabCount) ? _kAddButtonWidth : 0.0),
  );

  /// How wide each of [tabCount] tabs is, its gap included.
  double _slotFor(int tabCount) {
    final count = math.max(1, tabCount);
    final room =
        (_viewportFor(count) -
            (_pinsAddButton(count) ? 0.0 : _kAddButtonWidth)) /
        count;
    return (room - _kTabSpacing).clamp(_kMinTabWidth, _kMaxTabWidth) +
        _kTabSpacing;
  }

  TabStripReport? _report() {
    final strip = _stripKey.currentContext?.findRenderObject();
    final tabs = _tabsKey.currentContext?.findRenderObject();
    if (strip is! RenderBox || tabs is! RenderBox) return null;
    if (!strip.attached || !strip.hasSize || !tabs.hasSize) return null;

    return TabStripReport(
      bounds: strip.localToGlobal(Offset.zero) & strip.size,
      tabsOrigin: tabs.localToGlobal(Offset.zero),
      axis: Axis.horizontal,
      slotExtentFor: _slotFor,
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

  Widget _buildAddButton() {
    return SizedBox(
      width: _kAddButtonWidth,
      child: Center(
        child: BirdToolbarButton(
          glyph: BirdGlyph.plus,
          tooltip: 'New tab',
          size: 30,
          iconSize: 14,
          onPressed: () => BrowserTabActions.openNewTab(ref, context),
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
        Container(
          key: _stripKey,
          height: _kStripHeight,
          color: context.bird.frame,
          child: Row(
            children: [
              if (!Platform.isAndroid)
                WindowDragArea(
                  child: SizedBox(
                    height: double.infinity,
                    width: leadingControlsPadding,
                  ),
                ),
              SizedBox(
                width: _kLayoutToggleButtonWidth,
                child: BirdToolbarButton(
                  glyph: BirdGlyph.sidebar,
                  tooltip: 'Switch to vertical tabs',
                  size: 30,
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
                    // The leading window-button area and the layout toggle sit
                    // in the strip's Row *before* this builder, so `maxWidth`
                    // already excludes them; the only inset left to honour is
                    // the trailing window-button reservation. Strip content has
                    // to stop exactly at that boundary.
                    _contentWidth = math.max(
                      0.0,
                      constraints.maxWidth - trailingControlsPadding,
                    );
                    final count = tabIds.length;
                    final pinAddButton = _pinsAddButton(count);
                    final slot = _slotFor(count);
                    final tabsWidth = math.min(
                      _viewportFor(count),
                      slot * count + (pinAddButton ? 0 : _kAddButtonWidth),
                    );

                    // Everything the tabs do not use is window-drag surface,
                    // never less than the trailing reservation itself.
                    final dragAreaWidth = math.max(
                      trailingControlsPadding,
                      constraints.maxWidth -
                          tabsWidth -
                          (pinAddButton ? _kAddButtonWidth : 0.0),
                    );

                    return Row(
                      children: [
                        SizedBox(
                          width: tabsWidth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: _kStripPadding,
                            ),
                            child: KeyedSubtree(
                              key: _tabsKey,
                              child: TabStrip(
                                windowId: windowId,
                                axis: Axis.horizontal,
                                tabIds: tabIds,
                                closingTabIds: closingViewIds,
                                slotExtent: slot,
                                crossExtent: _kStripHeight - _kStripPadding * 2,
                                spacing: _kTabSpacing,
                                scrollController: _scrollController,
                                trailing: pinAddButton
                                    ? null
                                    : _buildAddButton(),
                                trailingExtent: pinAddButton
                                    ? 0
                                    : _kAddButtonWidth,
                                itemBuilder: (context, id) => BrowserTab(
                                  viewId: id,
                                  selected: id == widget.currentViewId,
                                  minWidth: _kMinTabWidth,
                                  width: slot - _kTabSpacing,
                                  onTabClosed: () => _closeTab(id),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (pinAddButton) _buildAddButton(),
                        SizedBox(
                          width: dragAreaWidth,
                          child: const WindowDragArea(
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

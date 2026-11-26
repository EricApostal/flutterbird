import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/windows/tab_drag_controller.dart';

/// A row, or column, of tabs that can be dragged: along it, out of it into a
/// window of their own, and into the strip of another window.
///
/// The strip places each tab itself rather than leaving it to a list, so that
/// the tab being dragged can be exactly where the mouse is while the others
/// slide to make room, whichever window it came from.
class TabStrip extends ConsumerStatefulWidget {
  const TabStrip({
    required this.windowId,
    required this.axis,
    required this.tabIds,
    required this.closingTabIds,
    required this.slotExtent,
    required this.crossExtent,
    required this.spacing,
    required this.scrollController,
    required this.itemBuilder,
    this.trailing,
    this.trailingExtent = 0,
    super.key,
  });

  static const Duration animationDuration = Duration(milliseconds: 180);
  static const Curve animationCurve = Curves.easeOutCubic;

  final int windowId;
  final Axis axis;

  /// In the order they are shown.
  final List<int> tabIds;

  /// The tabs on their way out, whose room closes up before they go.
  final Set<int> closingTabIds;

  /// How far along the strip a tab takes up, [spacing] included.
  final double slotExtent;

  /// How large a tab is across the strip.
  final double crossExtent;

  /// The gap after each tab.
  final double spacing;

  final ScrollController scrollController;
  final Widget Function(BuildContext context, int tabId) itemBuilder;

  /// What follows the last tab, such as the button that opens another.
  final Widget? trailing;
  final double trailingExtent;

  @override
  ConsumerState<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends ConsumerState<TabStrip> {
  /// How close to an end of the strip a dragged tab makes it scroll, and by
  /// how much each time.
  static const double _scrollMargin = 24;
  static const double _scrollStep = 10;

  bool _animateNewTabs = false;
  bool _scrollScheduled = false;

  // Which tabs have their room open: all but those on their way in or out.
  final Set<int> _expandedTabIds = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _animateNewTabs = true);
    });
  }

  /// A tab seen for the first time opens right away if it was there with the
  /// strip, and one frame later, so that it animates, if it is new. The tab
  /// being dragged is never new: it is as open as it was where it came from.
  void _syncExpanded(int? draggedTabId) {
    final present = widget.tabIds.toSet();
    _expandedTabIds.removeWhere((id) => !present.contains(id));

    final opening = <int>[];
    for (final id in present) {
      if (_expandedTabIds.contains(id)) continue;
      if (!_animateNewTabs || id == draggedTabId) {
        _expandedTabIds.add(id);
      } else {
        opening.add(id);
      }
    }

    if (opening.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _expandedTabIds.addAll(opening));
    });
  }

  // Scrolls a strip with more tabs than fit while a tab is dragged to its end.
  void _scrollToDragged(double leading) {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !widget.scrollController.hasClients) return;
      final position = widget.scrollController.position;
      final start = leading - position.pixels;
      final end = start + widget.slotExtent;

      var by = 0.0;
      if (start < _scrollMargin) by = -_scrollStep;
      if (end > position.viewportDimension - _scrollMargin) by = _scrollStep;
      final target = (position.pixels + by).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target != position.pixels) position.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final drags = ref.read(tabDragControllerProvider);
    return ListenableBuilder(
      listenable: drags,
      builder: (context, _) => _buildStrip(context, drags),
    );
  }

  Widget _buildStrip(BuildContext context, TabDragController drags) {
    final horizontal = widget.axis == Axis.horizontal;
    final draggedTabId = drags.draggedTabId;
    final draggedLeading = drags.leadingIn(widget.windowId);
    _syncExpanded(draggedTabId);

    Widget place({
      required Key key,
      required double at,
      required double extent,
      required bool underMouse,
      required Widget child,
    }) {
      return AnimatedPositioned(
        key: key,
        // Under the mouse there is nothing to animate. Let go, it slides from
        // there into its slot.
        duration: underMouse ? Duration.zero : TabStrip.animationDuration,
        curve: TabStrip.animationCurve,
        left: horizontal ? at : 0,
        top: horizontal ? 0 : at,
        width: horizontal ? extent : widget.crossExtent,
        height: horizontal ? widget.crossExtent : extent,
        child: child,
      );
    }

    var offset = 0.0;
    final items = <Widget>[];
    Widget? dragged;
    for (final tabId in widget.tabIds) {
      final isDragged = tabId == draggedTabId;
      final expanded =
          isDragged ||
          (_expandedTabIds.contains(tabId) &&
              !widget.closingTabIds.contains(tabId));
      final extent = expanded ? widget.slotExtent : 0.0;
      final underMouse = isDragged && draggedLeading != null;

      final item = place(
        key: ValueKey<int>(tabId),
        at: underMouse ? draggedLeading : offset,
        extent: extent,
        underMouse: underMouse,
        child: IgnorePointer(
          ignoring: !expanded,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: horizontal ? widget.slotExtent : widget.crossExtent,
              maxWidth: horizontal ? widget.slotExtent : widget.crossExtent,
              minHeight: horizontal ? widget.crossExtent : widget.slotExtent,
              maxHeight: horizontal ? widget.crossExtent : widget.slotExtent,
              child: Padding(
                padding: horizontal
                    ? EdgeInsets.only(right: widget.spacing)
                    : EdgeInsets.only(bottom: widget.spacing),
                child: _TabDragHandle(
                  windowId: widget.windowId,
                  tabId: tabId,
                  child: widget.itemBuilder(context, tabId),
                ),
              ),
            ),
          ),
        ),
      );
      offset += extent;
      if (isDragged) {
        dragged = item;
      } else {
        items.add(item);
      }
    }

    if (draggedLeading != null) _scrollToDragged(draggedLeading);

    final trailing = widget.trailing;
    final length = math.max(0.0, offset + widget.trailingExtent);

    return SingleChildScrollView(
      controller: widget.scrollController,
      scrollDirection: widget.axis,
      child: AnimatedContainer(
        // A tab being dragged along the end of the row must not be cut off
        // while the row grows to take it.
        duration: dragged == null ? TabStrip.animationDuration : Duration.zero,
        curve: TabStrip.animationCurve,
        width: horizontal ? length : widget.crossExtent,
        height: horizontal ? widget.crossExtent : length,
        child: Stack(
          children: [
            ...items,
            if (trailing != null)
              place(
                key: const ValueKey('trailing'),
                at: offset,
                extent: widget.trailingExtent,
                underMouse: false,
                child: trailing,
              ),
            // Last, so that it is drawn over the tabs it passes.
            ?dragged,
          ],
        ),
      ),
    );
  }
}

/// Turns a press on a tab that moves far enough into a drag of it.
class _TabDragHandle extends ConsumerStatefulWidget {
  const _TabDragHandle({
    required this.windowId,
    required this.tabId,
    required this.child,
  });

  final int windowId;
  final int tabId;
  final Widget child;

  @override
  ConsumerState<_TabDragHandle> createState() => _TabDragHandleState();
}

class _TabDragHandleState extends ConsumerState<_TabDragHandle> {
  /// How far a press has to move to be a drag and not a click.
  static const double _slop = 4;

  Offset? _down;
  bool _dragging = false;

  // Pointer events keep coming to a handle whose tab has been dragged out of
  // its window, and it is no longer there to do anything with them.
  TabDragController? _drags;

  void _onDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryMouseButton) return;
    _down = event.position;
    _dragging = false;
    _drags = ref.read(tabDragControllerProvider);
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null) return;

    if (_dragging) {
      _drags?.pointerMoved(widget.windowId, event.position);
      return;
    }
    if (!mounted || (event.position - down).distance <= _slop) return;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _dragging = true;
    _drags?.start(
      windowId: widget.windowId,
      tabId: widget.tabId,
      down: down,
      pointer: event.position,
      tabTopLeft: box.localToGlobal(Offset.zero),
    );
  }

  void _onEnd(PointerEvent event) {
    if (_dragging) _drags?.pointerReleased();
    _down = null;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onEnd,
      onPointerCancel: _onEnd,
      child: widget.child,
    );
  }
}

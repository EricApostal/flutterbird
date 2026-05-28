import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/tab.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_layout_mode.dart';
import 'package:window_manager/window_manager.dart';

const Duration _kSidebarTabAnimationDuration = Duration(milliseconds: 180);
const Curve _kSidebarTabAnimationCurve = Curves.easeOutCubic;

class BrowserVerticalTabSidebar extends ConsumerStatefulWidget {
  final int currentViewId;

  const BrowserVerticalTabSidebar({super.key, required this.currentViewId});

  @override
  ConsumerState<BrowserVerticalTabSidebar> createState() =>
      _BrowserVerticalTabSidebarState();
}

class _BrowserVerticalTabSidebarState
    extends ConsumerState<BrowserVerticalTabSidebar>
    with WindowListener {
  static const double _kSidebarWidth = 272;
  static const double _kTabHeight = 36;
  static const double _kMacControlsWidth = 78;

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
    }
  }

  @override
  void dispose() {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(browserTabControllerProvider);
    final theme = Theme.of(context);

    return Container(
      width: _kSidebarWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outline.withAlpha(36)),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(width: Platform.isMacOS ? _kMacControlsWidth : 8),
                Expanded(
                  child: DragToMoveArea(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Workspace',
                        style: theme.textTheme.labelLarge,
                      ),
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
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                  width: _kSidebarWidth - 16,
                  height: _kTabHeight,
                  animateOnMount: _animateNewTabs,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Tab'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,

                  foregroundColor: theme.colorScheme.onSurface,
                ),
                onPressed: () => BrowserTabActions.openNewTab(ref, context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedSidebarTabItem extends StatefulWidget {
  final int index;
  final int viewId;
  final bool selected;
  final double width;
  final double height;
  final bool animateOnMount;
  final bool Function() onCloseRequested;
  final VoidCallback onCloseCommitted;

  const _AnimatedSidebarTabItem({
    super.key,
    required this.index,
    required this.viewId,
    required this.selected,
    required this.width,
    required this.height,
    required this.animateOnMount,
    required this.onCloseRequested,
    required this.onCloseCommitted,
  });

  @override
  State<_AnimatedSidebarTabItem> createState() =>
      _AnimatedSidebarTabItemState();
}

class _AnimatedSidebarTabItemState extends State<_AnimatedSidebarTabItem> {
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

    await Future<void>.delayed(_kSidebarTabAnimationDuration);
    if (!mounted) return;
    widget.onCloseCommitted();
  }

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: widget.index,
      enabled: _isExpanded && !_isClosing,
      child: ClipRect(
        child: AnimatedContainer(
          duration: _kSidebarTabAnimationDuration,
          curve: _kSidebarTabAnimationCurve,
          height: _isExpanded ? widget.height + 6 : 0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              height: widget.height,
              width: widget.width,
              child: IgnorePointer(
                ignoring: _isClosing || !_isExpanded,
                child: BrowserTab(
                  viewId: widget.viewId,
                  selected: widget.selected,
                  variant: BrowserTabVariant.arcSidebar,
                  minWidth: widget.width,
                  width: widget.width,
                  minHeight: widget.height,
                  onTabClosed: _handleClose,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

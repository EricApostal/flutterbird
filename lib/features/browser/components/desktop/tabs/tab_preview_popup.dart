import 'dart:async';
import 'dart:ui' as ui;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/browser/state/tab_preview_cache.dart';
import 'package:rubisco_browser/features/windows/tab_drag_controller.dart';

// Where the preview sits relative to the tab it belongs to.
enum TabPreviewPlacement {
  // Under the tab, centered on it (the horizontal tab strip).
  below,

  // Beside the tab, centered on it vertically (the vertical tab sidebar).
  right,
}

// Shows a preview card of a tab's page while the pointer rests on the tab,
// like the Qt client: it appears after a short hover, never for the selected
// tab, and goes away as soon as the pointer leaves or presses the tab.
class TabPreviewHover extends StatefulWidget {
  const TabPreviewHover({
    super.key,
    required this.viewId,
    required this.selected,
    required this.placement,
    required this.child,
  });

  final int viewId;
  final bool selected;
  final TabPreviewPlacement placement;
  final Widget child;

  @override
  State<TabPreviewHover> createState() => _TabPreviewHoverState();
}

class _TabPreviewHoverState extends State<TabPreviewHover> {
  static const Duration _hoverDelay = Duration(milliseconds: 350);

  Timer? _timer;
  OverlayEntry? _entry;

  @override
  void didUpdateWidget(covariant TabPreviewHover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _hide();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.selected || _entry != null || _isDraggingTab()) return;
    _timer = Timer(_hoverDelay, _show);
  }

  void _show() {
    _timer = null;
    if (!mounted || widget.selected || _entry != null || _isDraggingTab()) {
      return;
    }

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    if (overlay == null || overlayBox is! RenderBox) return;

    final anchor = Rect.fromPoints(
      overlayBox.globalToLocal(box.localToGlobal(Offset.zero)),
      overlayBox.globalToLocal(
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      ),
    );

    final viewId = widget.viewId;
    final placement = widget.placement;
    _entry = OverlayEntry(
      builder: (context) => _TabPreviewOverlay(
        viewId: viewId,
        anchor: anchor,
        placement: placement,
      ),
    );
    overlay.insert(_entry!);
  }

  // A preview would only be in the way of a tab being dragged past.
  bool _isDraggingTab() => ProviderScope.containerOf(
    context,
    listen: false,
  ).read(tabDragControllerProvider).isDragging;

  void _hide() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry.remove();
    entry.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _schedule(),
      onExit: (_) => _hide(),
      child: Listener(
        // Pressing the tab starts a click or a drag; the card only gets in the
        // way of either.
        onPointerDown: (_) => _hide(),
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      ),
    );
  }
}

class _TabPreviewOverlay extends StatelessWidget {
  const _TabPreviewOverlay({
    required this.viewId,
    required this.anchor,
    required this.placement,
  });

  final int viewId;
  final Rect anchor;
  final TabPreviewPlacement placement;

  @override
  Widget build(BuildContext context) {
    // The card only shows, so it lets the mouse through to what is under it.
    return IgnorePointer(
      child: CustomSingleChildLayout(
        delegate: _TabPreviewLayoutDelegate(
          anchor: anchor,
          placement: placement,
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * -4),
              child: child,
            ),
          ),
          child: TabPreviewCard(viewId: viewId),
        ),
      ),
    );
  }
}

class _TabPreviewLayoutDelegate extends SingleChildLayoutDelegate {
  _TabPreviewLayoutDelegate({required this.anchor, required this.placement});

  static const double _gap = 6;
  static const double _edgeMargin = 8;

  final Rect anchor;
  final TabPreviewPlacement placement;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    double x;
    double y;

    switch (placement) {
      case TabPreviewPlacement.below:
        x = anchor.center.dx - childSize.width / 2;
        y = anchor.bottom + _gap;
        // No room underneath: sit above the tab instead.
        if (y + childSize.height > size.height - _edgeMargin) {
          y = anchor.top - _gap - childSize.height;
        }
      case TabPreviewPlacement.right:
        x = anchor.right + _gap;
        y = anchor.center.dy - childSize.height / 2;
        // No room to the right: sit on the other side of the tab.
        if (x + childSize.width > size.width - _edgeMargin) {
          x = anchor.left - _gap - childSize.width;
        }
    }

    return Offset(
      _clamp(x, _edgeMargin, size.width - childSize.width - _edgeMargin),
      _clamp(y, _edgeMargin, size.height - childSize.height - _edgeMargin),
    );
  }

  // Unlike num.clamp, tolerates the card being larger than the room.
  double _clamp(double value, double min, double max) {
    if (max < min) return min;
    return value < min ? min : (value > max ? max : value);
  }

  @override
  bool shouldRelayout(covariant _TabPreviewLayoutDelegate oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.placement != placement;
}

// The card itself: the page's thumbnail when the tab has one, then its title
// and address. A tab that has never been on screen has no thumbnail, so its
// card is the title and address alone.
class TabPreviewCard extends ConsumerWidget {
  const TabPreviewCard({super.key, required this.viewId});

  static const double thumbnailWidth = 320;
  static const double thumbnailHeight = 180;

  final int viewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(browserTabProvider(viewId));
    if (controller == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 10,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: thumbnailWidth + 16,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<ui.Image?>(
              valueListenable: TabPreviewCache.instance.listenableFor(viewId),
              builder: (context, image, child) {
                if (image == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: thumbnailWidth,
                      height: thumbnailHeight,
                      color: scheme.surfaceContainerLowest,
                      // A page taller than 16:9 loses its bottom, as in a
                      // browser's own tab previews.
                      child: RawImage(
                        image: image,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ValueListenableBuilder<String>(
                valueListenable: controller.titleNotifier,
                builder: (context, title, child) => Text(
                  title.isEmpty ? 'New Tab' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: controller.urlNotifier,
              builder: (context, url, child) {
                if (url.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                  child: Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

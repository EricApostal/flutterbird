import 'package:bird_core/bird_core.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/browser/components/desktop/tabs/tab_preview_popup.dart';
import 'package:rubisco_browser/features/browser/state/tab_actions.dart';
import 'package:ladybird/ladybird.dart';

enum BrowserTabVariant { horizontal, arcSidebar }

class BrowserTab extends ConsumerStatefulWidget {
  final int viewId;
  final bool selected;
  final void Function() onTabClosed;
  final BrowserTabVariant variant;
  final double minWidth;
  final double? width;
  final double? minHeight;

  const BrowserTab({
    super.key,
    required this.viewId,
    required this.selected,
    required this.onTabClosed,
    this.variant = BrowserTabVariant.horizontal,
    this.minWidth = 170,
    this.width,
    this.minHeight,
  });

  @override
  ConsumerState<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends ConsumerState<BrowserTab> {
  bool _isHovering = false;
  final GlobalKey _closeButtonKey = GlobalKey();

  Widget _buildTabLeadingIcon(LadybirdController browserTab) {
    return ValueListenableBuilder<bool>(
      valueListenable: browserTab.isLoadingNotifier,
      builder: (context, isLoading, child) {
        if (isLoading) {
          return const Center(widthFactor: 1, child: BirdSpinner(size: 15));
        }

        return ValueListenableBuilder<dynamic>(
          valueListenable: browserTab.faviconNotifier,
          builder: (context, image, child) {
            if (image != null) {
              return RawImage(
                image: image,
                width: 16,
                height: 16,
                filterQuality: FilterQuality.high,
              );
            }
            return BirdIcon(
              BirdGlyph.globe,
              size: 16,
              color: context.bird.textSecondary,
            );
          },
        );
      },
    );
  }

  Widget _buildTabTitle(LadybirdController browserTab) {
    return ValueListenableBuilder<String>(
      valueListenable: browserTab.titleNotifier,
      builder: (context, title, child) {
        return Text(
          title,
          style: context.birdText(size: BirdTextSize.small),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final browserTab = ref.watch(browserTabProvider(widget.viewId));
    if (browserTab == null) return const SizedBox.shrink();

    final isSidebarVariant = widget.variant == BrowserTabVariant.arcSidebar;
    final showCloseButton = !isSidebarVariant || widget.selected || _isHovering;

    return TabPreviewHover(
      viewId: widget.viewId,
      selected: widget.selected,
      placement: isSidebarVariant
          ? TabPreviewPlacement.right
          : TabPreviewPlacement.below,
      child: _buildTab(context, browserTab, isSidebarVariant, showCloseButton),
    );
  }

  Widget _buildTab(
    BuildContext context,
    LadybirdController browserTab,
    bool isSidebarVariant,
    bool showCloseButton,
  ) {
    final colors = context.bird;

    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _isHovering = true;
        });
      },
      onExit: (_) {
        setState(() {
          _isHovering = false;
        });
      },
      // Activate on press, not on release: the tab and its page then change on
      // the first frame after the button goes down, instead of on the first
      // frame after the click finishes (which is what made a switch feel a
      // frame behind -- the click's own duration, plus the up->frame hop).
      // Chrome behaves the same way; a drag that turns into a reorder simply
      // activates the tab it starts on.
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons & kPrimaryMouseButton == 0) return;
          if (_isOverCloseButton(event.position)) return;
          _activate(context);
        },
        child: Semantics(
          button: true,
          selected: widget.selected,
          // For accessibility actions, which do not press a pointer.
          onTap: () => _activate(context),
          child: Container(
            width: widget.width,
            constraints: BoxConstraints(
              minWidth: widget.minWidth,
              minHeight: widget.minHeight ?? 32,
            ),
            // Room for the selected tab's shadow, which the strip would clip.
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: widget.selected
                  ? colors.tabSelected
                  : (_isHovering ? colors.tabHover : null),
              borderRadius: BorderRadius.circular(BirdRadius.control),
              boxShadow: widget.selected
                  ? [BoxShadow(color: colors.tabShadow, blurRadius: 3)]
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 9),
                _buildTabLeadingIcon(browserTab),
                const SizedBox(width: 8),
                Expanded(child: _buildTabTitle(browserTab)),
                const SizedBox(width: 4),
                IgnorePointer(
                  ignoring: !showCloseButton,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    opacity: showCloseButton ? 1 : 0,
                    child: BirdToolbarButton(
                      key: _closeButtonKey,
                      glyph: BirdGlyph.close,
                      size: 22,
                      iconSize: 10,
                      onPressed: widget.onTabClosed,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Whether a press landed on the close button, which is inside the tab and so
  // also inside the listener that activates the tab.
  bool _isOverCloseButton(Offset globalPosition) {
    final box = _closeButtonKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(globalPosition);
  }

  void _activate(BuildContext context) {
    if (widget.selected) return;
    HapticFeedback.lightImpact();
    BrowserTabActions.showTab(context, widget.viewId);
  }
}

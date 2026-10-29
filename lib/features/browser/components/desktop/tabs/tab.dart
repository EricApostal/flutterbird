import 'package:bird_core/bird_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  Widget _buildTabLeadingIcon(LadybirdController browserTab, ThemeData theme) {
    return ValueListenableBuilder<bool>(
      valueListenable: browserTab.isLoadingNotifier,
      builder: (context, isLoading, child) {
        if (isLoading) {
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: const CircularProgressIndicator.adaptive(),
            ),
          );
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
            return Icon(Icons.public, size: 16, color: theme.iconTheme.color);
          },
        );
      },
    );
  }

  Widget _buildTabTitle(
    LadybirdController browserTab,
    TextStyle? titleStyle,
    Color titleColor,
  ) {
    return ValueListenableBuilder<String>(
      valueListenable: browserTab.titleNotifier,
      builder: (context, title, child) {
        return Text(
          title,
          style: titleStyle!.copyWith(color: titleColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final browserTab = ref.watch(browserTabProvider(widget.viewId))!;

    final theme = Theme.of(context);
    final isSidebarVariant = widget.variant == BrowserTabVariant.arcSidebar;
    final showCloseButton = !isSidebarVariant || widget.selected || _isHovering;

    final borderRadius = isSidebarVariant
        ? BorderRadius.circular(10)
        : const BorderRadius.vertical(
            top: Radius.circular(8),
            bottom: Radius.circular(8),
          );
    final titleStyle = isSidebarVariant
        ? theme.textTheme.bodyMedium
        : theme.textTheme.bodySmall;

    return MouseRegion(
      onEnter: (_) {
        if (!isSidebarVariant) return;
        setState(() {
          _isHovering = true;
        });
      },
      onExit: (_) {
        if (!isSidebarVariant) return;
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
        child: InkWell(
          borderRadius: borderRadius,
          // Kept for the ink splash and for accessibility actions, which invoke
          // the tap rather than press a pointer.
          onTap: () => _activate(context),
          child: Container(
            width: widget.width,
            constraints: BoxConstraints(
              minWidth: widget.minWidth,
              minHeight: widget.minHeight ?? 36,
            ),
            decoration: BoxDecoration(
              color: widget.selected
                  ? theme.colorScheme.primaryContainer
                  : Color.lerp(
                      Colors.black,
                      theme.colorScheme.primaryContainer,
                      0.5,
                    )!,
              borderRadius: borderRadius,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: isSidebarVariant ? 10 : 12,
                        right: 6,
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: _buildTabLeadingIcon(browserTab, theme),
                          ),
                          Expanded(
                            child: _buildTabTitle(
                              browserTab,
                              titleStyle,
                              theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: !showCloseButton,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    opacity: showCloseButton ? 1 : 0,
                    child: IconButton(
                      key: _closeButtonKey,
                      icon: Icon(Icons.close, size: isSidebarVariant ? 15 : 16),
                      onPressed: widget.onTabClosed,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isSidebarVariant ? 6 : 8),
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
    context.go('/browser/tab/${widget.viewId}');
  }
}

import 'package:bird_core/bird_core.dart';
import 'package:fluent_ui/fluent_ui.dart' as f;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/frontend/abstraction/frontend_layer.dart';
import 'package:flutterbird/features/frontend/components/adaptive_widgets.dart';
import 'package:go_router/go_router.dart';

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

  Widget _buildTabLeadingIcon(dynamic browserTab, ThemeData theme) {
    return ValueListenableBuilder<bool>(
      valueListenable: browserTab.isLoadingNotifier,
      builder: (context, isLoading, child) {
        if (isLoading) {
          return const FrontendTabLoadingIndicator();
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
    dynamic browserTab,
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

  Widget _buildFluentHorizontalTab(
    BuildContext context,
    dynamic browserTab,
    ThemeData theme,
    TextStyle? titleStyle,
    FrontendTabVisuals tabVisuals,
  ) {
    return SizedBox(
      width: widget.width,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minWidth,
          minHeight: widget.minHeight ?? 36,
        ),
        child: f.TabData(
          selected: widget.selected,
          onPressed: () {
            HapticFeedback.lightImpact();
            context.go('/browser/tab/${widget.viewId}');
          },
          onClose: widget.onTabClosed,
          reorderIndex: null,
          animationDuration: const Duration(milliseconds: 120),
          animationCurve: Curves.easeOut,
          visibilityMode: f.CloseButtonVisibilityMode.always,
          tabWidthBehavior: f.TabWidthBehavior.equal,
          child: f.Tab(
            text: _buildTabTitle(browserTab, titleStyle, tabVisuals.titleColor),
            body: const SizedBox.shrink(),
            icon: _buildTabLeadingIcon(browserTab, theme),
            backgroundColor: WidgetStateColor.resolveWith(
              (states) => Colors.transparent,
            ),
            selectedBackgroundColor: WidgetStateColor.resolveWith(
              (states) => tabVisuals.backgroundColor,
            ),
            onClosed: widget.onTabClosed,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final browserTab = ref.watch(browserTabProvider(widget.viewId))!;
    final frontend = FrontendScope.of(context);

    final theme = Theme.of(context);
    final isSidebarVariant = widget.variant == BrowserTabVariant.arcSidebar;
    final showCloseButton = !isSidebarVariant || widget.selected || _isHovering;
    final tabVisuals = frontend.resolveTabVisuals(
      context: context,
      selected: widget.selected,
      sidebarVariant: isSidebarVariant,
    );
    final borderRadius = isSidebarVariant
        ? BorderRadius.circular(10)
        : const BorderRadius.vertical(
            top: Radius.circular(8),
            bottom: Radius.circular(8),
          );
    final titleStyle = isSidebarVariant
        ? theme.textTheme.bodyMedium
        : theme.textTheme.bodySmall;

    if (frontend.flavor == FrontendFlavor.fluent && !isSidebarVariant) {
      return _buildFluentHorizontalTab(
        context,
        browserTab,
        theme,
        titleStyle,
        tabVisuals,
      );
    }

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
      child: FrontendTabSurface(
        borderRadius: borderRadius,
        onPressed: () {
          HapticFeedback.lightImpact();
          context.go('/browser/tab/${widget.viewId}');
        },
        child: Container(
          width: widget.width,
          constraints: BoxConstraints(
            minWidth: widget.minWidth,
            minHeight: widget.minHeight ?? 36,
          ),
          decoration: BoxDecoration(
            color: tabVisuals.backgroundColor,
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
                            tabVisuals.titleColor,
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
                  child: FrontendIconButton(
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
    );
  }
}

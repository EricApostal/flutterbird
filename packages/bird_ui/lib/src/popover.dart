import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'button.dart';
import 'icons.dart';
import 'menu.dart';
import 'theme.dart';

/// The surface of whatever floats: popovers, cards over the page, dialogs.
class BirdPanel extends StatelessWidget {
  const BirdPanel({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.constraints,
    this.padding = EdgeInsets.zero,
    this.radius = BirdRadius.panel,
    this.color,
  });

  final Widget child;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return Container(
      width: width,
      height: height,
      constraints: constraints,
      decoration: BoxDecoration(
        color: color ?? colors.panel,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: colors.shadow, blurRadius: 18, offset: const Offset(0, 6)),
          BoxShadow(color: colors.shadow.withValues(alpha: 0.16), blurRadius: 3, offset: const Offset(0, 1)),
        ],
      ),
      // Over the contents, so that rows reaching the edge do not hide it.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.panelBorder),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: DefaultTextStyle(style: context.birdText(), child: child),
    );
  }
}

/// A panel's name, with room for buttons.
class BirdPanelHeader extends StatelessWidget {
  const BirdPanelHeader(this.title, {super.key, this.actions = const [], this.onBack, this.onClose});

  final String title;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                if (onBack != null)
                  BirdToolbarButton(glyph: BirdGlyph.back, size: 28, iconSize: 13, tooltip: 'Back', onPressed: onBack)
                else
                  const SizedBox(width: 8),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.birdText(weight: FontWeight.w600),
                  ),
                ),
                ...actions,
                if (onClose != null)
                  BirdToolbarButton(glyph: BirdGlyph.close, size: 28, iconSize: 11, tooltip: 'Close', onPressed: onClose),
              ],
            ),
          ),
        ),
        const BirdSeparator(),
      ],
    );
  }
}

class BirdSeparator extends StatelessWidget {
  const BirdSeparator({super.key, this.vertical = false, this.length, this.space = 0});

  final bool vertical;
  final double? length;

  /// Clear room on both sides of the line.
  final double space;

  @override
  Widget build(BuildContext context) => Container(
    width: vertical ? 1 : length,
    height: vertical ? length : 1,
    margin: vertical ? EdgeInsets.symmetric(horizontal: space) : EdgeInsets.symmetric(vertical: space),
    color: context.bird.separator,
  );
}

/// Which edges of a popover and of what it hangs from line up.
enum BirdPopoverAlign { start, end, stretch }

/// Something that hangs from [child] while [controller] shows it: a panel from
/// a toolbar button, or suggestions from a field.
///
/// A press outside it and [child] hides it, but not one in a menu or a dialog
/// that was opened from it. With [takeFocus], it gets the keyboard and Escape
/// hides it.
class BirdPopover extends StatefulWidget {
  const BirdPopover({
    super.key,
    required this.controller,
    required this.popoverBuilder,
    required this.child,
    this.align = BirdPopoverAlign.start,
    this.gap = 4,
    this.takeFocus = true,
    this.dismissible = true,
    this.onDismiss,
  });

  final OverlayPortalController controller;
  final WidgetBuilder popoverBuilder;
  final Widget child;
  final BirdPopoverAlign align;
  final double gap;
  final bool takeFocus;

  /// Whether a press outside hides it.
  final bool dismissible;

  /// Called when the popover hides itself.
  final VoidCallback? onDismiss;

  @override
  State<BirdPopover> createState() => _BirdPopoverState();
}

class _BirdPopoverState extends State<BirdPopover> {
  // What is hung and what it hangs from count as one place to press.
  final Object _group = Object();

  void _dismiss() {
    if (!widget.controller.isShowing) return;
    widget.controller.hide();
    widget.onDismiss?.call();
  }

  void _pressedOutside(PointerDownEvent event) {
    if (!widget.dismissible || BirdMenus.isOpen) return;
    // A dialog over this window is its own business.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: widget.controller,
      overlayChildBuilder: _buildPopover,
      child: TapRegion(groupId: _group, child: widget.child),
    );
  }

  Widget _buildPopover(BuildContext context, OverlayChildLayoutInfo info) {
    final anchor = MatrixUtils.transformRect(info.childPaintTransform, Offset.zero & info.childSize);
    Widget content = TapRegion(
      groupId: _group,
      onTapOutside: _pressedOutside,
      // A press in here leaves the caret of a field this hangs from.
      child: TextFieldTapRegion(child: Builder(builder: widget.popoverBuilder)),
    );
    if (widget.takeFocus) {
      content = FocusScope(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) {
            return KeyEventResult.ignored;
          }
          _dismiss();
          return KeyEventResult.handled;
        },
        child: content,
      );
    }
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _PopoverLayout(anchor, widget.align, widget.gap),
        child: content,
      ),
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, this.align, this.gap);

  final Rect anchor;
  final BirdPopoverAlign align;
  final double gap;

  static const double _margin = 4;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final below = constraints.maxHeight - anchor.bottom - gap - _margin;
    final height = below.clamp(0.0, constraints.maxHeight);
    final width = (constraints.maxWidth - _margin * 2).clamp(0.0, constraints.maxWidth);
    if (align == BirdPopoverAlign.stretch) {
      return BoxConstraints(minWidth: anchor.width, maxWidth: anchor.width, maxHeight: height);
    }
    return BoxConstraints(maxWidth: width, maxHeight: height);
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    if (align == BirdPopoverAlign.stretch) return Offset(anchor.left, anchor.bottom + gap);
    final wanted = align == BirdPopoverAlign.start ? anchor.left : anchor.right - child.width;
    final most = size.width - child.width - _margin;
    final x = most < _margin ? _margin : wanted.clamp(_margin, most);
    return Offset(x, anchor.bottom + gap);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.anchor != anchor || old.align != align || old.gap != gap;
}

import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'pressable.dart';
import 'theme.dart';
import 'tooltip.dart';

enum BirdButtonKind {
  /// The one thing a panel or dialog is there to do. At most one.
  primary,

  /// Everything else.
  secondary,

  /// Destroys something.
  danger,

  /// Looks like words until the pointer is over it.
  ghost,
}

/// A button with words.
class BirdButton extends StatelessWidget {
  const BirdButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = BirdButtonKind.secondary,
    this.glyph,
    this.expand = false,
    this.small = false,
    this.autofocus = false,
    this.focusNode,
  });

  const BirdButton.primary(
    this.label, {
    super.key,
    required this.onPressed,
    this.glyph,
    this.expand = false,
    this.small = false,
    this.autofocus = false,
    this.focusNode,
  }) : kind = BirdButtonKind.primary;

  final String label;

  /// Null disables.
  final VoidCallback? onPressed;
  final BirdButtonKind kind;
  final BirdGlyph? glyph;

  /// As wide as there is room for, as the buttons stacked in a panel are.
  final bool expand;
  final bool small;
  final bool autofocus;
  final FocusNode? focusNode;

  (Color, Color) _look(BirdColors colors, BirdPressState state) {
    Color of(Color rest, Color hover, Color active) =>
        state.pressed ? active : (state.hovered ? hover : rest);
    return switch (kind) {
      BirdButtonKind.primary => (of(colors.accent, colors.accentHover, colors.accentActive), colors.onAccent),
      BirdButtonKind.secondary => (of(colors.control, colors.controlHover, colors.controlActive), colors.text),
      BirdButtonKind.danger => (of(colors.danger, colors.dangerHover, colors.dangerHover), colors.onDanger),
      BirdButtonKind.ghost => (of(const Color(0x00000000), colors.hover, colors.pressed), colors.text),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return BirdPressable(
      onPressed: onPressed,
      autofocus: autofocus,
      focusNode: focusNode,
      builder: (context, state) {
        final (background, foreground) = _look(colors, state);
        return Opacity(
          opacity: state.enabled ? 1 : 0.4,
          // The ring stands clear of the button, so that it shows on a button
          // of the ring's own colour.
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BirdRadius.control + 2),
              border: Border.all(color: state.focused ? colors.accent : const Color(0x00000000), width: 2),
            ),
            child: Container(
              constraints: BoxConstraints(minHeight: small ? 24 : 30, minWidth: small ? 0 : 64),
              padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14),
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(BirdRadius.control)),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (glyph case final glyph?) ...[
                    BirdIcon(glyph, size: 14, color: foreground),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.birdText(
                        color: foreground,
                        size: small ? BirdTextSize.small : BirdTextSize.body,
                        weight: kind == BirdButtonKind.ghost ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A square button with an icon, as in a toolbar.
class BirdToolbarButton extends StatelessWidget {
  const BirdToolbarButton({
    super.key,
    this.glyph,
    this.icon,
    required this.onPressed,
    this.onSecondaryTapDown,
    this.tooltip = '',
    this.active = false,
    this.color,
    this.size = 32,
    this.iconSize = 16,
    this.focusNode,
  }) : assert(glyph != null || icon != null, 'A button needs something on it.');

  final BirdGlyph? glyph;

  /// In place of [glyph], for an image.
  final Widget? icon;
  final VoidCallback? onPressed;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final String tooltip;

  /// Held down, such as while what it opens is open.
  final bool active;
  final Color? color;
  final double size;
  final double iconSize;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return BirdTooltip(
      message: tooltip,
      child: BirdPressable(
        onPressed: onPressed,
        onSecondaryTapDown: onSecondaryTapDown,
        focusNode: focusNode,
        semanticLabel: tooltip,
        builder: (context, state) => BirdFocusRing(
          visible: state.focused,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: state.pressed || active
                  ? colors.pressed
                  : state.hovered
                  ? colors.hover
                  : null,
              borderRadius: BorderRadius.circular(BirdRadius.control),
            ),
            child: Opacity(
              opacity: state.enabled ? 1 : 0.35,
              child: icon ?? BirdIcon(glyph!, size: iconSize, color: color ?? colors.icon),
            ),
          ),
        ),
      ),
    );
  }
}

/// Words that go somewhere.
class BirdLink extends StatelessWidget {
  const BirdLink(this.label, {super.key, required this.onPressed, this.size = BirdTextSize.body});

  final String label;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return BirdPressable(
      onPressed: onPressed,
      cursor: SystemMouseCursors.click,
      builder: (context, state) {
        final color = !state.enabled
            ? colors.textDisabled
            : state.hovered
            ? colors.linkHover
            : colors.link;
        return BirdFocusRing(
          visible: state.focused,
          child: Text(
            label,
            style: context.birdText(color: color, size: size).copyWith(
              decoration: state.hovered ? TextDecoration.underline : TextDecoration.none,
              decorationColor: color,
            ),
          ),
        );
      },
    );
  }
}

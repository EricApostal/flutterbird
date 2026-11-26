import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Rebuilds with whether the pointer is over it.
class BirdHover extends StatefulWidget {
  const BirdHover({
    super.key,
    required this.builder,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.onEnter,
    this.onExit,
    this.cursor = MouseCursor.defer,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;
  final MouseCursor cursor;
  final HitTestBehavior behavior;

  @override
  State<BirdHover> createState() => _BirdHoverState();
}

class _BirdHoverState extends State<BirdHover> {
  bool _hovered = false;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  // A double tap is timed by hand: waiting to rule one out would put a delay
  // on every single click.
  void _tap() {
    final now = DateTime.now();
    final double =
        widget.onDoubleTap != null && now.difference(_lastTap) < kDoubleTapTimeout;
    _lastTap = double ? DateTime.fromMillisecondsSinceEpoch(0) : now;
    if (double) {
      widget.onDoubleTap!();
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onDoubleTap != null;
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onEnter?.call();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onExit?.call();
      },
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: interactive ? _tap : null,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: widget.builder(context, _hovered),
      ),
    );
  }
}


/// How a [BirdPressable] is being touched.
@immutable
class BirdPressState {
  const BirdPressState({this.hovered = false, this.pressed = false, this.focused = false, this.enabled = true});

  final bool hovered;
  final bool pressed;

  /// Focused in a way that should show, which is to say from the keyboard.
  final bool focused;
  final bool enabled;
}

/// What every button is made of: hover and press, a focus ring for the
/// keyboard, and Return and Space. A click does not take the keyboard from
/// what has it, as buttons on the desktop do not.
class BirdPressable extends StatefulWidget {
  const BirdPressable({
    super.key,
    required this.builder,
    this.onPressed,
    this.onSecondaryTapDown,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.cursor = SystemMouseCursors.basic,
  });

  final Widget Function(BuildContext context, BirdPressState state) builder;

  /// Null disables.
  final VoidCallback? onPressed;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final MouseCursor cursor;

  @override
  State<BirdPressable> createState() => _BirdPressableState();
}

class _BirdPressableState extends State<BirdPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  // Bound here, nearer than a dialog's own Return, so that Return on a
  // focused button presses that button.
  static const Map<ShortcutActivator, Intent> _shortcuts = {
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  void _press(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor: enabled ? widget.cursor : SystemMouseCursors.basic,
        shortcuts: _shortcuts,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        // A disabled button still reports the pointer, for its tooltip.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          onTapDown: enabled ? (_) => _press(true) : null,
          onTapUp: enabled ? (_) => _press(false) : null,
          onTapCancel: enabled ? () => _press(false) : null,
          onSecondaryTapDown: widget.onSecondaryTapDown,
          child: widget.builder(
            context,
            BirdPressState(
              hovered: _hovered && enabled,
              pressed: _pressed && enabled,
              focused: _focused && enabled,
              enabled: enabled,
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring around whatever the keyboard is on.
class BirdFocusRing extends StatelessWidget {
  const BirdFocusRing({super.key, required this.visible, required this.child, this.radius = BirdRadius.control});

  final bool visible;
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: visible ? Border.all(color: context.bird.accent, width: 2) : null,
    ),
    child: child,
  );
}

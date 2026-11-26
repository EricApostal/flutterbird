import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'button.dart';
import 'icons.dart';
import 'text_input.dart';
import 'theme.dart';

/// A box to type in.
class BirdTextField extends StatefulWidget {
  const BirdTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue = '',
    this.placeholder = '',
    this.onChanged,
    this.onSubmitted,
    this.onKey,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.errorText,
    this.keepFocusOnSubmit = false,
    this.semanticLabel,
  });

  /// One of its own is made where there is none.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String initialValue;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;

  /// What is wrong with what was typed, shown under the box.
  final String? errorText;
  final bool keepFocusOnSubmit;
  final String? semanticLabel;

  @override
  State<BirdTextField> createState() => _BirdTextFieldState();
}

class _BirdTextFieldState extends State<BirdTextField> {
  TextEditingController? _ownController;
  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController(text: widget.initialValue));
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void dispose() {
    _ownController?.dispose();
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    final error = widget.errorText;
    _node.canRequestFocus = widget.enabled;
    final box = ListenableBuilder(
      listenable: _node,
      builder: (context, child) {
        final focused = _node.hasFocus;
        final ring = error != null ? colors.danger : colors.accent;
        return Container(
          height: 30,
          decoration: BoxDecoration(
            color: colors.inputBackground,
            borderRadius: BorderRadius.circular(BirdRadius.control),
            border: Border.all(
              color: focused || error != null ? ring : colors.inputBorder.withValues(alpha: 0.7),
            ),
            // The second pixel of the ring, outside, so that nothing moves.
            boxShadow: focused ? [BoxShadow(color: ring, spreadRadius: 1)] : null,
          ),
          child: child,
        );
      },
      child: Row(
        children: [
          const SizedBox(width: 8),
          if (widget.leading case final leading?) ...[leading, const SizedBox(width: 6)],
          Expanded(
            child: BirdTextInput(
              controller: _controller,
              focusNode: _node,
              placeholder: widget.placeholder,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              onKey: widget.onKey,
              autofocus: widget.autofocus,
              readOnly: !widget.enabled,
              obscureText: widget.obscureText,
              keepFocusOnSubmit: widget.keepFocusOnSubmit,
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
          if (widget.trailing case final trailing?) ...[const SizedBox(width: 4), trailing],
          const SizedBox(width: 6),
        ],
      ),
    );
    return Semantics(
      label: widget.semanticLabel,
      textField: true,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.4,
        child: IgnorePointer(
          ignoring: !widget.enabled,
          child: error == null
              ? box
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    box,
                    const SizedBox(height: 4),
                    Text(error, style: context.birdText(color: colors.danger, size: BirdTextSize.small)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A field to search or filter with: a glass, and a button that empties it.
/// Escape empties it too.
class BirdSearchField extends StatefulWidget {
  const BirdSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    required this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<BirdSearchField> createState() => _BirdSearchFieldState();
}

class _BirdSearchFieldState extends State<BirdSearchField> {
  TextEditingController? _ownController;
  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) => BirdTextField(
    controller: _controller,
    focusNode: widget.focusNode,
    placeholder: widget.placeholder,
    autofocus: widget.autofocus,
    keepFocusOnSubmit: true,
    onChanged: widget.onChanged,
    onKey: (event) {
      // With nothing to empty, Escape is for whatever holds the field.
      if (event is! KeyDownEvent ||
          event.logicalKey != LogicalKeyboardKey.escape ||
          _controller.text.isEmpty) {
        return KeyEventResult.ignored;
      }
      _clear();
      return KeyEventResult.handled;
    },
    leading: BirdIcon(BirdGlyph.search, size: 13, color: context.bird.textSecondary),
    trailing: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _controller.text.isEmpty
          ? const SizedBox.shrink()
          : BirdToolbarButton(glyph: BirdGlyph.close, size: 20, iconSize: 10, tooltip: 'Clear', onPressed: _clear),
    ),
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'menu.dart';
import 'theme.dart';

/// A text field of the desktop kind: a caret, a selection made with the mouse,
/// and the platform's editing keys.
class BirdTextInput extends StatefulWidget {
  const BirdTextInput({
    super.key,
    required this.controller,
    this.focusNode,
    this.style,
    this.placeholder = '',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.maxLines = 1,
    this.expands = false,
    this.onKey,
    this.inputFormatters,
    this.readOnly = false,
    this.scrollController,
    this.keepFocusOnSubmit = true,
    this.obscureText = false,
    this.padding = EdgeInsets.zero,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextStyle? style;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final int? maxLines;
  final bool expands;

  /// Sees keys before the field does.
  final KeyEventResult Function(KeyEvent event)? onKey;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final ScrollController? scrollController;

  /// Whether Return leaves the keyboard here, as in a field that is used over
  /// and over, or gives it up, as in one that is filled in once.
  final bool keepFocusOnSubmit;
  final bool obscureText;

  /// Room around the line that is still the field: a press in it lands in the
  /// text.
  final EdgeInsetsGeometry padding;

  @override
  State<BirdTextInput> createState() => _BirdTextInputState();
}

class _BirdTextInputState extends State<BirdTextInput>
    implements TextSelectionGestureDetectorBuilderDelegate {
  @override
  final GlobalKey<EditableTextState> editableTextKey =
      GlobalKey<EditableTextState>();

  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  FocusOnKeyEventCallback? _previousHandler;
  FocusNode? _handled;

  void _bindKeys() {
    if (_handled == _node) return;
    _unbindKeys();
    _handled = _node;
    _previousHandler = _node.onKeyEvent;
    _node.onKeyEvent = (node, event) {
      final result = widget.onKey?.call(event) ?? KeyEventResult.ignored;
      if (result != KeyEventResult.ignored) return result;
      return _previousHandler?.call(node, event) ?? KeyEventResult.ignored;
    };
  }

  void _unbindKeys() {
    _handled?.onKeyEvent = _previousHandler;
    _handled = null;
  }

  @override
  void dispose() {
    _unbindKeys();
    _ownNode?.dispose();
    super.dispose();
  }

  void _showEditMenu(Offset position) {
    _node.requestFocus();
    final editable = editableTextKey.currentState;
    if (editable == null) return;
    final selection = widget.controller.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;
    final command = defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl+';
    showBirdMenu(context, position, [
      BirdMenuItem('Cut', enabled: hasSelection && !widget.readOnly, shortcut: '${command}X', onSelected: () => editable.cutSelection(SelectionChangedCause.toolbar)),
      BirdMenuItem('Copy', enabled: hasSelection, shortcut: '${command}C', onSelected: () => editable.copySelection(SelectionChangedCause.toolbar)),
      BirdMenuItem('Paste', enabled: !widget.readOnly, shortcut: '${command}V', onSelected: () => editable.pasteText(SelectionChangedCause.toolbar)),
      const BirdMenuItem.separator(),
      BirdMenuItem('Select All', shortcut: '${command}A', onSelected: () => editable.selectAll(SelectionChangedCause.toolbar)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    _bindKeys();
    final colors = context.bird;
    final style = widget.style ?? context.birdText();
    final editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: _node,
      style: style,
      cursorColor: colors.text,
      cursorWidth: 1,
      backgroundCursorColor: colors.textSecondary,
      selectionColor: colors.textSelection,
      autofocus: widget.autofocus,
      maxLines: widget.expands ? null : widget.maxLines,
      expands: widget.expands,
      readOnly: widget.readOnly,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textCapitalization: TextCapitalization.none,
      keyboardType: widget.maxLines == 1 && !widget.expands ? TextInputType.text : TextInputType.multiline,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onEditingComplete: widget.keepFocusOnSubmit ? () {} : null,
      obscureText: widget.obscureText,
      rendererIgnoresPointer: true,
      scrollController: widget.scrollController,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryButton) _showEditMenu(event.position);
        },
        child: _gestures.buildGestureDetector(
          behavior: HitTestBehavior.translucent,
          child: Padding(
            padding: widget.padding,
            child: Stack(
              alignment: widget.expands ? Alignment.topLeft : Alignment.centerLeft,
              fit: widget.expands ? StackFit.expand : StackFit.loose,
              children: [
              if (widget.placeholder.isNotEmpty)
                ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => widget.controller.text.isEmpty
                      ? IgnorePointer(
                          child: Text(
                            widget.placeholder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(color: colors.textSecondary),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                editable,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'theme.dart';
import 'widgets.dart';

/// How an inline edit ended, which says what to edit next.
enum EditEnd { enter, tab, backTab, blur }

/// What completes the text before the caret: the candidates, and how many
/// characters at the end of the text one of them replaces.
typedef CompletionSource = FutureOr<(List<String>, int)> Function(String before);

/// A list of candidates under a field, driven by the field's keys.
class DtCompletionPopup extends StatelessWidget {
  const DtCompletionPopup({
    super.key,
    required this.matches,
    required this.selected,
    required this.onPick,
    required this.typed,
  });

  final List<String> matches;
  final int selected;
  final ValueChanged<int> onPick;
  final int typed;

  static const double rowHeight = 17;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final visible = matches.length.clamp(1, 10);
    final first = (selected - visible + 1).clamp(0, matches.length - visible);
    final longest = matches.fold(0, (m, s) => s.length > m ? s.length : m);
    return Container(
      width: (longest * 6.8 + 22).clamp(120.0, 360.0),
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: colors.popup,
        border: Border.all(color: colors.popupBorder),
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = first; i < first + visible; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => onPick(i),
              child: Container(
                height: rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                color: i == selected ? colors.selection : null,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: matches[i].substring(0, typed.clamp(0, matches[i].length)),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: matches[i].substring(typed.clamp(0, matches[i].length))),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.monoStyle(color: i == selected ? colors.selectionText : colors.textStrong),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The field that takes the place of a piece of text while it is edited, as in
/// the markup and rules views.
class DtInlineEditor extends StatefulWidget {
  const DtInlineEditor({
    super.key,
    required this.initial,
    required this.onCommit,
    required this.onCancel,
    this.style,
    this.completions,
    this.completionStartsOpen = false,
    this.commitCharacters = const {},
    this.multiline = false,
    this.minWidth = 24,
    this.maxWidth = 520,
    this.placeholder = '',
  });

  final String initial;
  final void Function(String value, EditEnd end) onCommit;
  final VoidCallback onCancel;
  final TextStyle? style;
  final CompletionSource? completions;
  final bool completionStartsOpen;

  /// Characters that commit instead of being typed, such as ":" after a
  /// property name.
  final Set<String> commitCharacters;
  final bool multiline;
  final double minWidth;
  final double maxWidth;
  final String placeholder;

  @override
  State<DtInlineEditor> createState() => _DtInlineEditorState();
}

class _DtInlineEditorState extends State<DtInlineEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  final FocusNode _focus = FocusNode(debugLabel: 'inline editor');
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  List<String> _matches = const [];
  int _selected = 0;
  int _typed = 0;
  bool _finished = false;
  bool _hadFocus = false;
  int _completionGeneration = 0;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _lastText = widget.initial;
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      if (widget.completionStartsOpen) _complete();
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _hadFocus = true;
    } else if (_hadFocus) {
      _finish(EditEnd.blur);
    }
  }

  void _finish(EditEnd end) {
    if (_finished) return;
    _finished = true;
    widget.onCommit(_controller.text, end);
  }

  void _cancel() {
    if (_finished) return;
    _finished = true;
    widget.onCancel();
  }

  Future<void> _complete() async {
    final source = widget.completions;
    if (source == null) return;
    final generation = ++_completionGeneration;
    final selection = _controller.selection;
    final cursor = selection.isValid ? selection.extentOffset : _controller.text.length;
    final (matches, typed) = await source(_controller.text.substring(0, cursor));
    if (!mounted || generation != _completionGeneration) return;
    setState(() {
      _matches = matches;
      _typed = typed;
      _selected = 0;
      matches.isEmpty ? _portal.hide() : _portal.show();
    });
  }

  void _hideCompletions() {
    _completionGeneration++;
    if (_matches.isEmpty) return;
    setState(() => _matches = const []);
    _portal.hide();
  }

  void _accept(int index) {
    final value = _matches[index];
    final selection = _controller.selection;
    final cursor = selection.isValid ? selection.extentOffset : _controller.text.length;
    final start = (cursor - _typed).clamp(0, cursor);
    final text = _controller.text.replaceRange(start, cursor, value);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _lastText = text;
    _hideCompletions();
  }

  void _onChanged(String text) {
    // A commit character typed at the end finishes the edit.
    if (text.length == _lastText.length + 1 &&
        text.startsWith(_lastText) &&
        widget.commitCharacters.contains(text[text.length - 1])) {
      final quotes = RegExp('["\']').allMatches(_lastText).length;
      final open = '('.allMatches(_lastText).length - ')'.allMatches(_lastText).length;
      if (quotes.isEven && open <= 0) {
        _controller.text = _lastText;
        _finish(EditEnd.tab);
        return;
      }
    }
    _lastText = text;
    setState(() {});
    if (text.isEmpty) {
      _hideCompletions();
    } else {
      _complete();
    }
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (_matches.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _selected = (_selected + 1) % _matches.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _selected = (_selected - 1) % _matches.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
        _accept(_selected);
        _finish(key == LogicalKeyboardKey.tab ? (shift ? EditEnd.backTab : EditEnd.tab) : EditEnd.enter);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _hideCompletions();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight &&
          _controller.selection.extentOffset >= _controller.text.length) {
        _accept(_selected);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    final command = HardwareKeyboard.instance.isMetaPressed || HardwareKeyboard.instance.isControlPressed;
    if (key == LogicalKeyboardKey.enter) {
      if (widget.multiline && !command) return KeyEventResult.ignored;
      _finish(EditEnd.enter);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _finish(shift ? EditEnd.backTab : EditEnd.tab);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final style = widget.style ?? context.monoStyle(color: colors.textStrong);
    final painter = TextPainter(
      text: TextSpan(text: _controller.text.isEmpty ? widget.placeholder : _controller.text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = (painter.width + 12).clamp(widget.minWidth, widget.maxWidth);
    painter.dispose();
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          showWhenUnlinked: false,
          child: DtTheme(
            colors: colors,
            child: DtCompletionPopup(
              matches: _matches,
              selected: _selected,
              typed: _typed,
              onPick: (i) {
                _accept(i);
                _focus.requestFocus();
              },
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: Container(
          width: widget.multiline ? widget.maxWidth : width,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: colors.inputBackground,
            border: Border.all(color: colors.accent),
            borderRadius: BorderRadius.circular(2),
          ),
          child: DtTextInput(
            controller: _controller,
            focusNode: _focus,
            style: style,
            placeholder: widget.placeholder,
            maxLines: widget.multiline ? null : 1,
            onChanged: _onChanged,
            onKey: _onKey,
          ),
        ),
      ),
    );
  }
}

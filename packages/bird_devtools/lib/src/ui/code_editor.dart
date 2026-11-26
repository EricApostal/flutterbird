import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../util/syntax.dart';
import 'code_view.dart';
import 'theme.dart';
import 'widgets.dart';

/// A text controller that colours what it holds as code.
class CodeEditingController extends TextEditingController {
  CodeEditingController({super.text, required this.language});

  SyntaxLanguage language;
  DtColors colors = DtColors.light;

  String? _highlighted;
  List<List<Token>> _tokens = const [];

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.length > 300000) return TextSpan(style: style, text: text);
    final lines = text.split('\n');
    if (_highlighted != text) {
      _highlighted = text;
      _tokens = highlightLines(lines, language);
    }
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          ...codeSpans(colors, lines[i], _tokens[i]),
          if (i + 1 < lines.length) const TextSpan(text: '\n'),
        ],
      ],
    );
  }
}

/// Inserts two spaces for Tab, and keeps a line's indentation on Enter.
KeyEventResult handleCodeKeys(TextEditingController controller, KeyEvent event, ValueChanged<String>? onChanged) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
  final selection = controller.selection;
  if (!selection.isValid) return KeyEventResult.ignored;
  void insert(String text) {
    final next = controller.text.replaceRange(selection.start, selection.end, text);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
    onChanged?.call(next);
  }

  final keyboard = HardwareKeyboard.instance;
  if (keyboard.isMetaPressed || keyboard.isControlPressed || keyboard.isAltPressed) {
    return KeyEventResult.ignored;
  }
  if (event.logicalKey == LogicalKeyboardKey.tab && !keyboard.isShiftPressed) {
    insert('  ');
    return KeyEventResult.handled;
  }
  if (event.logicalKey == LogicalKeyboardKey.enter) {
    final before = controller.text.substring(0, selection.start);
    final line = before.substring(before.lastIndexOf('\n') + 1);
    var indent = RegExp(r'^[ \t]*').firstMatch(line)!.group(0)!;
    if (line.trimRight().endsWith('{')) indent += '  ';
    insert('\n$indent');
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

/// An editor for code, with line numbers.
class DtCodeEditor extends StatefulWidget {
  const DtCodeEditor({
    super.key,
    required this.controller,
    this.onChanged,
    this.onKey,
    this.focusNode,
    this.autofocus = false,
    this.lineNumbers = true,
    this.placeholder = '',
  });

  final CodeEditingController controller;
  final ValueChanged<String>? onChanged;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool lineNumbers;
  final String placeholder;

  @override
  State<DtCodeEditor> createState() => _DtCodeEditorState();
}

class _DtCodeEditorState extends State<DtCodeEditor> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    widget.controller.colors = colors;
    final style = context.monoStyle(color: colors.textStrong);
    final characterWidth = monoCharacterWidth(style);
    return ColoredBox(
      color: colors.body,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final lines = widget.controller.text.split('\n');
          var longest = 0;
          for (final line in lines) {
            if (line.length > longest) longest = line.length;
          }
          final gutter = widget.lineNumbers
              ? '${lines.length}'.length.clamp(3, 7) * characterWidth + 18
              : 0.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.lineNumbers)
                SizedBox(
                  width: gutter,
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _vertical,
                      builder: (context, _) => CustomPaint(
                        painter: _LineNumberPainter(
                          lines.length,
                          _vertical.hasClients ? _vertical.offset : 0,
                          style.copyWith(color: colors.textDim),
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Scrollbar2D(
                    horizontal: _horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: (longest.clamp(0, 4000) * characterWidth + 40).clamp(constraints.maxWidth, double.infinity),
                        height: constraints.maxHeight,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: DtTextInput(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            autofocus: widget.autofocus,
                            style: style,
                            placeholder: widget.placeholder,
                            expands: true,
                            scrollController: _vertical,
                            onChanged: widget.onChanged,
                            onKey: (event) {
                              final result = widget.onKey?.call(event) ?? KeyEventResult.ignored;
                              if (result != KeyEventResult.ignored) return result;
                              return handleCodeKeys(widget.controller, event, widget.onChanged);
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LineNumberPainter extends CustomPainter {
  _LineNumberPainter(this.count, this.offset, this.style);
  final int count;
  final double offset;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    var line = (offset / DtFonts.codeLine).floor();
    if (line < 0) line = 0;
    for (; line < count; line++) {
      final y = line * DtFonts.codeLine - offset;
      if (y > size.height) break;
      final painter = TextPainter(
        text: TextSpan(text: '${line + 1}', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(size.width - painter.width - 6, y));
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_LineNumberPainter old) =>
      old.count != count || old.offset != offset || old.style != style;
}

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../util/syntax.dart';
import 'theme.dart';

/// [line] coloured by its [tokens], with each place [needle] occurs marked.
List<InlineSpan> codeSpans(
  DtColors colors,
  String line,
  List<Token> tokens, {
  String needle = '',
}) {
  final marks = <(int, int)>[];
  if (needle.isNotEmpty) {
    final lowerLine = line.toLowerCase();
    final lowerNeedle = needle.toLowerCase();
    for (var at = lowerLine.indexOf(lowerNeedle); at >= 0; at = lowerLine.indexOf(lowerNeedle, at + lowerNeedle.length)) {
      marks.add((at, at + lowerNeedle.length));
    }
  }
  final spans = <InlineSpan>[];
  void add(int start, int end, Color? color) {
    if (end <= start) return;
    var at = start;
    for (final (from, to) in marks) {
      if (to <= at || from >= end) continue;
      final a = from < at ? at : from;
      final b = to > end ? end : to;
      if (a > at) {
        spans.add(TextSpan(text: line.substring(at, a), style: TextStyle(color: color)));
      }
      spans.add(
        TextSpan(
          text: line.substring(a, b),
          style: TextStyle(color: color, backgroundColor: colors.searchHit),
        ),
      );
      at = b;
    }
    if (at < end) {
      spans.add(TextSpan(text: line.substring(at, end), style: TextStyle(color: color)));
    }
  }

  var position = 0;
  for (final token in tokens) {
    if (token.start < position || token.end > line.length) continue;
    add(position, token.start, null);
    add(token.start, token.end, colors.syntax(token.kind));
    position = token.end;
  }
  add(position, line.length, null);
  return spans;
}

/// The width of one character of the code font.
double monoCharacterWidth(TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: 'MMMMMMMMMM', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width / 10;
  painter.dispose();
  return width;
}

/// What the gutter draws for a line.
class GutterMark {
  const GutterMark(this.color, {this.hollow = false});
  final Color color;
  final bool hollow;
}

/// A line of a source to bring into view. A new [serial] asks again.
class CodeReveal {
  const CodeReveal(this.line, this.serial);
  final int line;
  final int serial;
}

/// Source code to read: line numbers, colours, marks in the gutter, and text
/// that can be selected and copied.
class DtCodeView extends StatefulWidget {
  const DtCodeView({
    super.key,
    required this.lines,
    required this.tokens,
    this.gutterMarks = const {},
    this.highlightedLine,
    this.highlightedColumn,
    this.dimmedLines,
    this.needle = '',
    this.reveal,
    this.onGutterTap,
    this.onGutterMenu,
    this.onLineMenu,
    this.onCursorLine,
    this.scrollController,
    this.onHoverWord,
    this.onHoverEnd,
  });

  final List<String> lines;
  final List<List<Token>> tokens;

  /// By line number, from 1.
  final Map<int, GutterMark> gutterMarks;

  /// The line execution is paused on, and where on it.
  final int? highlightedLine;
  final int? highlightedColumn;

  /// Which line numbers are faded, such as those no breakpoint can be on.
  final bool Function(int line)? dimmedLines;
  final String needle;
  final CodeReveal? reveal;
  final void Function(int line)? onGutterTap;
  final void Function(int line, Offset position)? onGutterMenu;
  final void Function(int line, Offset position, String selected)? onLineMenu;
  final void Function(int line, int column)? onCursorLine;
  final ScrollController? scrollController;

  /// Told the expression under the resting pointer.
  final void Function(String expression, Offset position)? onHoverWord;
  final VoidCallback? onHoverEnd;

  @override
  State<DtCodeView> createState() => _DtCodeViewState();
}

class _DtCodeViewState extends State<DtCodeView> {
  late final ScrollController _vertical = widget.scrollController ?? ScrollController();
  final ScrollController _horizontal = ScrollController();
  final FocusNode _selectionFocus = FocusNode(debugLabel: 'code');
  String _selected = '';
  int _revealed = -1;
  String _hovered = '';

  @override
  void initState() {
    super.initState();
    _scheduleReveal();
  }

  @override
  void didUpdateWidget(DtCodeView old) {
    super.didUpdateWidget(old);
    _scheduleReveal();
  }

  void _scheduleReveal() {
    final reveal = widget.reveal;
    if (reveal == null || reveal.serial == _revealed || widget.lines.length <= 1) return;
    _revealed = reveal.serial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      final position = _vertical.position;
      final top = (reveal.line - 1) * DtFonts.codeLine;
      final visibleFrom = position.pixels;
      final visibleTo = visibleFrom + position.viewportDimension;
      if (top < visibleFrom + DtFonts.codeLine || top > visibleTo - 3 * DtFonts.codeLine) {
        _vertical.jumpTo(
          (top - position.viewportDimension / 3).clamp(0.0, position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void dispose() {
    if (widget.scrollController == null) _vertical.dispose();
    _horizontal.dispose();
    _selectionFocus.dispose();
    super.dispose();
  }

  static final RegExp _expressionCharacter = RegExp(r'[\w$.]');

  void _hover(int index, double x, double characterWidth, Offset global) {
    if (widget.onHoverWord == null) return;
    final line = widget.lines[index];
    final column = (x / characterWidth).floor();
    var expression = '';
    if (column >= 0 && column < line.length && RegExp(r'[\w$]').hasMatch(line[column])) {
      var start = column;
      var end = column + 1;
      // The whole chain up to the word under the pointer: "a.b.c".
      while (start > 0 && _expressionCharacter.hasMatch(line[start - 1])) {
        start--;
      }
      while (end < line.length && RegExp(r'[\w$]').hasMatch(line[end])) {
        end++;
      }
      final tokens = index < widget.tokens.length ? widget.tokens[index] : const <Token>[];
      final kind = tokens.where((t) => t.start <= column && column < t.end).firstOrNull?.kind;
      if (kind == TokenKind.variable || kind == TokenKind.property) {
        expression = line.substring(start, end);
      }
    }
    final key = '$index $expression';
    if (key == _hovered) return;
    _hovered = key;
    if (expression.isEmpty) {
      widget.onHoverEnd?.call();
    } else {
      widget.onHoverWord!(expression, global);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final style = context.monoStyle(color: colors.textStrong);
    final characterWidth = monoCharacterWidth(style);
    final digits = '${widget.lines.length}'.length.clamp(3, 7);
    final gutter = digits * characterWidth + 18;
    var longest = 0;
    for (final line in widget.lines) {
      if (line.length > longest) longest = line.length;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (gutter + 8 + longest.clamp(0, 6000) * characterWidth + 40)
            .clamp(constraints.maxWidth, double.infinity);
        return ColoredBox(
          color: colors.body,
          child: Scrollbar2D(
            horizontal: _horizontal,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: SelectableRegion(
                  focusNode: _selectionFocus,
                  selectionControls: emptyTextSelectionControls,
                  onSelectionChanged: (content) => _selected = content?.plainText ?? '',
                  contextMenuBuilder: (context, state) => const SizedBox.shrink(),
                  child: ListView.builder(
                    controller: _vertical,
                    itemExtent: DtFonts.codeLine,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: widget.lines.length,
                    itemBuilder: (context, index) => _line(context, index, gutter, digits, characterWidth, style),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _line(
    BuildContext context,
    int index,
    double gutter,
    int digits,
    double characterWidth,
    TextStyle style,
  ) {
    final colors = context.dt;
    final number = index + 1;
    final paused = widget.highlightedLine == number;
    final mark = widget.gutterMarks[number];
    final line = widget.lines[index];
    final shown = line.length > 6000 ? '${line.substring(0, 6000)}…' : line;
    final tokens = index < widget.tokens.length ? widget.tokens[index] : const <Token>[];
    final column = widget.highlightedColumn;
    return Container(
      color: paused ? colors.paused : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: gutter + 8,
            top: 0,
            bottom: 0,
            right: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.text,
              onHover: (event) => _hover(index, event.localPosition.dx, characterWidth, event.position),
              onExit: (_) {
                _hovered = '';
                widget.onHoverEnd?.call();
              },
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  final at = (event.localPosition.dx / characterWidth).round().clamp(0, line.length);
                  widget.onCursorLine?.call(number, at);
                  if (event.buttons == kSecondaryButton) {
                    widget.onLineMenu?.call(number, event.position, _selected);
                  }
                },
                child: Text.rich(
                  TextSpan(children: codeSpans(colors, shown, tokens, needle: widget.needle)),
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ),
          if (paused && column != null)
            Positioned(
              left: gutter + 8 + column * characterWidth - 1,
              top: 1,
              child: Container(width: 2, height: DtFonts.codeLine - 2, color: colors.pausedBorder),
            ),
          // The gutter stays put while the code scrolls sideways.
          AnimatedBuilder(
            animation: _horizontal,
            builder: (context, child) => Positioned(
              left: _horizontal.hasClients ? _horizontal.offset : 0,
              top: 0,
              bottom: 0,
              width: gutter,
              child: child!,
            ),
            child: SelectionContainer.disabled(
              child: MouseRegion(
                cursor: widget.onGutterTap == null ? MouseCursor.defer : SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onGutterTap == null ? null : () => widget.onGutterTap!(number),
                  onSecondaryTapDown: widget.onGutterMenu == null
                      ? null
                      : (details) => widget.onGutterMenu!(number, details.globalPosition),
                  child: CustomPaint(
                    painter: _GutterPainter(paused ? colors.paused : colors.body, mark),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        '$number',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        style: style.copyWith(
                          color: mark != null && !mark.hollow
                              ? const Color(0xFFFFFFFF)
                              : widget.dimmedLines?.call(number) ?? false
                              ? colors.textDim.withValues(alpha: 0.45)
                              : colors.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  _GutterPainter(this.background, this.mark);
  final Color background;
  final GutterMark? mark;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final mark = this.mark;
    if (mark == null) return;
    // Firefox's breakpoint: a tab pointing into the code.
    final path = Path()
      ..moveTo(4, 1)
      ..lineTo(size.width - 7, 1)
      ..lineTo(size.width - 1, size.height / 2)
      ..lineTo(size.width - 7, size.height - 1)
      ..lineTo(4, size.height - 1)
      ..arcToPoint(Offset(2, size.height - 3), radius: const Radius.circular(2))
      ..lineTo(2, 3)
      ..arcToPoint(const Offset(4, 1), radius: const Radius.circular(2))
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = mark.color
        ..style = mark.hollow ? PaintingStyle.stroke : PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_GutterPainter old) =>
      old.background != background || old.mark?.color != mark?.color || old.mark?.hollow != mark?.hollow;
}

/// A sideways scrollbar along the bottom, which a mouse needs.
class Scrollbar2D extends StatelessWidget {
  const Scrollbar2D({super.key, required this.horizontal, required this.child});

  final ScrollController horizontal;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawScrollbar(
    controller: horizontal,
    thickness: 7,
    radius: const Radius.circular(4),
    padding: const EdgeInsets.all(1),
    thumbColor: context.dt.textDim.withValues(alpha: 0.45),
    scrollbarOrientation: ScrollbarOrientation.bottom,
    notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
    child: child,
  );
}

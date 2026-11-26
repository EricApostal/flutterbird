import 'syntax.dart';

/// Source reformatted for reading, and where each of its lines came from.
class PrettyPrinted {
  PrettyPrinted(this.lines, this.origins);

  final List<String> lines;

  /// For each line, the line (from 1) and column (from 0) of the original its
  /// first token was at.
  final List<(int, int)> origins;

  String get text => lines.join('\n');

  /// The first formatted line (from 1) at or after the original [line].
  int formattedLineFor(int line, [int column = 0]) {
    var best = 1;
    for (var i = 0; i < origins.length; i++) {
      final (originLine, originColumn) = origins[i];
      if (originLine < line || (originLine == line && originColumn <= column)) {
        best = i + 1;
      }
    }
    return best;
  }

  (int, int) originalFor(int formattedLine) =>
      origins[(formattedLine - 1).clamp(0, origins.length - 1)];
}

class _Piece {
  _Piece(this.text, this.kind, this.line, this.column, this.newlineBefore, this.spaceBefore);
  final String text;
  final TokenKind kind;
  final int line;
  final int column;
  final bool newlineBefore;
  final bool spaceBefore;
}

/// The tokens of a whole source, those that span lines made one.
List<_Piece> _tokenize(String source, SyntaxLanguage language) {
  final lines = source.split('\n');
  // Highlighting a long line is skipped, but formatting one is the point.
  final pieces = <_Piece>[];
  final tokens = _highlightUnbounded(lines, language);
  var pendingNewline = false;
  for (var i = 0; i < lines.length; i++) {
    var previousEnd = 0;
    for (final token in tokens[i]) {
      final text = lines[i].substring(token.start, token.end);
      final space = token.start > previousEnd;
      previousEnd = token.end;
      final continues =
          token.start == 0 &&
          pieces.isNotEmpty &&
          pendingNewline &&
          (token.kind == TokenKind.comment && !text.startsWith('/') ||
              token.kind == TokenKind.string && pieces.last.kind == TokenKind.string && _isOpenTemplate(pieces.last.text));
      if (continues) {
        final last = pieces.removeLast();
        pieces.add(
          _Piece('${last.text}\n$text', last.kind, last.line, last.column, last.newlineBefore, last.spaceBefore),
        );
      } else {
        pieces.add(
          _Piece(text, token.kind, i + 1, token.start, pendingNewline, space || (pendingNewline && pieces.isNotEmpty)),
        );
      }
      pendingNewline = false;
    }
    pendingNewline = true;
  }
  return pieces;
}

bool _isOpenTemplate(String text) =>
    text.startsWith('`') && (text.length == 1 || !text.endsWith('`'));

List<List<Token>> _highlightUnbounded(
  List<String> lines,
  SyntaxLanguage language,
) {
  const chunk = 19000;
  if (lines.every((line) => line.length <= chunk)) {
    return highlightLines(lines, language);
  }
  // Long lines are tokenized in stretches cut at safe places.
  final parts = <String>[];
  final owners = <(int, int)>[];
  for (var i = 0; i < lines.length; i++) {
    var start = 0;
    final line = lines[i];
    do {
      var end = (start + chunk).clamp(0, line.length);
      if (end < line.length) {
        final cut = line.lastIndexOf(RegExp(r'[;{}]'), end);
        if (cut > start) end = cut + 1;
      }
      parts.add(line.substring(start, end));
      owners.add((i, start));
      start = end;
    } while (start < line.length);
  }
  final result = List.generate(lines.length, (_) => <Token>[]);
  final tokens = highlightLines(parts, language);
  for (var p = 0; p < parts.length; p++) {
    final (line, offset) = owners[p];
    result[line].addAll([
      for (final t in tokens[p]) Token(t.start + offset, t.end + offset, t.kind),
    ]);
  }
  return result;
}

class _Writer {
  final List<String> lines = [];
  final List<(int, int)> origins = [];
  final StringBuffer _current = StringBuffer();
  (int, int)? _origin;
  int indent = 0;

  bool get isLineEmpty => _current.isEmpty;

  void write(String text, int line, int column, {bool space = false}) {
    if (_current.isEmpty) {
      _current.write('  ' * indent);
      _origin = (line, column);
    } else if (space) {
      _current.write(' ');
    }
    final parts = text.split('\n');
    _current.write(parts.first);
    for (var i = 1; i < parts.length; i++) {
      _flush();
      _origin = (line + i, 0);
      _current.write(parts[i]);
    }
  }

  void _flush() {
    lines.add(_current.toString());
    origins.add(_origin ?? (1, 0));
    _current.clear();
  }

  void newline() {
    if (_current.isNotEmpty) _flush();
  }

  PrettyPrinted finish() {
    newline();
    if (lines.isEmpty) {
      lines.add('');
      origins.add((1, 0));
    }
    return PrettyPrinted(lines, origins);
  }
}

PrettyPrinted prettyPrintJavaScript(String source) {
  final pieces = _tokenize(source, SyntaxLanguage.javascript);
  final out = _Writer();
  // The brackets that are open, innermost last.
  final open = <String>[];
  _Piece? previous;
  var operatorRun = false;

  const punctuationNoSpaceBefore = {'.', ',', ';', ')', ']', '(', '['};
  const operatorCharacters = '=+-*/%<>!&|^?:~';

  bool isWordLike(_Piece p) =>
      p.kind != TokenKind.punctuation;

  for (var i = 0; i < pieces.length; i++) {
    final piece = pieces[i];
    final text = piece.text;
    final next = i + 1 < pieces.length ? pieces[i + 1] : null;

    if (piece.kind == TokenKind.comment) {
      if (piece.newlineBefore) out.newline();
      out.write(text, piece.line, piece.column, space: true);
      if (text.startsWith('//') || (next?.newlineBefore ?? true)) out.newline();
      previous = piece;
      continue;
    }

    final last = previous;
    var space = false;
    if (last != null && !out.isLineEmpty) {
      final lastText = last.text;
      final isOperator = piece.kind == TokenKind.punctuation && operatorCharacters.contains(text);
      final lastIsOperator = last.kind == TokenKind.punctuation && operatorCharacters.contains(lastText);
      if (isWordLike(piece) && isWordLike(last)) {
        space = true;
      } else if (isOperator && lastIsOperator && !piece.spaceBefore) {
        space = false;
      } else if (isOperator) {
        // "a++" and "!a" stay joined, "a + b" is spread out.
        final unary = (text == '!' || text == '~') ||
            piece.spaceBefore == false && next != null && !next.spaceBefore && (text == '+' || text == '-') && (next.text == text || lastText == text);
        space = !unary && !(text == ':' ) && !(text == '?' && next?.text == '.');
        if (text == ':' && open.isNotEmpty && open.last == '?') space = true;
      } else if (lastIsOperator) {
        final prefix = (lastText == '!' || lastText == '~') ||
            (!piece.spaceBefore && (lastText == '-' || lastText == '+') && !operatorRun && _unaryContext(pieces, i - 1)) ||
            (lastText == '.' );
        space = !prefix;
        if (lastText == '?' && text == '.') space = false;
      } else if (lastText == ',' || lastText == ';') {
        space = true;
      } else if (lastText == ')' && (isWordLike(piece) || text == '{')) {
        space = true;
      } else if (text == '{' && lastText != '(' && lastText != '[') {
        space = true;
      } else if (lastText == '}' && isWordLike(piece)) {
        space = true;
      } else if (text == '(' && last.kind == TokenKind.keyword && const {'if', 'for', 'while', 'switch', 'catch', 'return', 'function'}.contains(lastText)) {
        space = lastText != 'function';
      } else if (!punctuationNoSpaceBefore.contains(text) && lastText != '.' && lastText != '(' && lastText != '[' && lastText != '{') {
        space = piece.spaceBefore;
      }
      if (lastText == '.') space = false;
    }
    operatorRun = piece.kind == TokenKind.punctuation && operatorCharacters.contains(text);

    switch (text) {
      case '{' when piece.kind == TokenKind.punctuation:
        out.write(text, piece.line, piece.column, space: space);
        open.add('{');
        if (next?.text == '}') break;
        out.indent++;
        out.newline();
      case '}' when piece.kind == TokenKind.punctuation:
        if (open.isNotEmpty) open.removeLast();
        if (previous?.text != '{') {
          out.newline();
          if (out.indent > 0) out.indent--;
        }
        out.write(text, piece.line, piece.column);
        if (next != null &&
            !const {';', ',', ')', ']', '.', '(', 'else', 'catch', 'finally', 'while'}.contains(next.text)) {
          out.newline();
        }
      case '(' || '[' when piece.kind == TokenKind.punctuation:
        out.write(text, piece.line, piece.column, space: space);
        open.add(text);
      case ')' || ']' when piece.kind == TokenKind.punctuation:
        if (open.isNotEmpty) open.removeLast();
        out.write(text, piece.line, piece.column);
      case ';' when piece.kind == TokenKind.punctuation:
        out.write(text, piece.line, piece.column);
        if (open.isEmpty || open.last == '{') out.newline();
      case ',' when piece.kind == TokenKind.punctuation:
        out.write(text, piece.line, piece.column);
        if (open.isNotEmpty && open.last == '{') out.newline();
      default:
        // Where the author broke a line, a statement may end with no
        // semicolon, so the break stays.
        if (piece.newlineBefore &&
            last != null &&
            !out.isLineEmpty &&
            isWordLike(piece) &&
            (isWordLike(last) || last.text == ')' || last.text == ']')) {
          out.newline();
        }
        out.write(text, piece.line, piece.column, space: space);
    }
    previous = piece;
  }
  return out.finish();
}

bool _unaryContext(List<_Piece> pieces, int operatorIndex) {
  if (operatorIndex <= 0) return true;
  final before = pieces[operatorIndex - 1];
  if (before.kind == TokenKind.keyword) return true;
  return before.kind == TokenKind.punctuation && !')]}'.contains(before.text);
}

PrettyPrinted prettyPrintCss(String source) {
  final pieces = _tokenize(source, SyntaxLanguage.css);
  final out = _Writer();
  var inValue = false;
  var depth = 0;
  _Piece? previous;
  for (var i = 0; i < pieces.length; i++) {
    final piece = pieces[i];
    final text = piece.text;
    if (piece.kind == TokenKind.comment) {
      out.newline();
      out.write(text, piece.line, piece.column);
      out.newline();
      previous = piece;
      continue;
    }
    switch (text) {
      case '{':
        out.write(text, piece.line, piece.column, space: true);
        depth++;
        out.indent = depth;
        out.newline();
        inValue = false;
      case '}':
        out.newline();
        if (depth > 0) depth--;
        out.indent = depth;
        out.write(text, piece.line, piece.column);
        out.newline();
        inValue = false;
      case ';':
        out.write(text, piece.line, piece.column);
        out.newline();
        inValue = false;
      case ',':
        out.write(text, piece.line, piece.column);
        if (depth == 0) out.newline();
      case ':':
        out.write(text, piece.line, piece.column, space: depth == 0 && piece.spaceBefore);
        if (depth > 0 && previous?.kind == TokenKind.property) {
          inValue = true;
        }
      default:
        final last = previous?.text ?? '';
        final space = !out.isLineEmpty &&
            (last == ':' && inValue || last == ',' || (piece.spaceBefore && last != '(' && text != ')'));
        out.write(text, piece.line, piece.column, space: space);
    }
    previous = piece;
  }
  return out.finish();
}

/// Whether source looks to have been squeezed onto few lines.
bool looksMinified(String source) {
  if (source.length < 600) return false;
  final lines = '\n'.allMatches(source).length + 1;
  return source.length / lines > 200;
}

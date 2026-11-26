/// What a run of source text is, for colouring it.
enum TokenKind {
  plain,
  keyword,
  string,
  number,
  comment,
  literal,
  function,
  property,
  punctuation,
  tag,
  attributeName,
  attributeValue,
  selector,
  atRule,
  variable,
  regexp,
}

class Token {
  const Token(this.start, this.end, this.kind);
  final int start;
  final int end;
  final TokenKind kind;
}

enum SyntaxLanguage { javascript, css, html, json, plain }

SyntaxLanguage languageFor(String contentType, String url) {
  final type = contentType.toLowerCase();
  final path = url.split('?').first.split('#').first.toLowerCase();
  if (type.contains('json') || path.endsWith('.json')) {
    return SyntaxLanguage.json;
  }
  if (type.contains('javascript') ||
      type.contains('ecmascript') ||
      path.endsWith('.js') ||
      path.endsWith('.mjs')) {
    return SyntaxLanguage.javascript;
  }
  if (type.contains('css') || path.endsWith('.css')) return SyntaxLanguage.css;
  if (type.contains('html') ||
      type.contains('xml') ||
      type.contains('svg') ||
      path.endsWith('.html')) {
    return SyntaxLanguage.html;
  }
  return SyntaxLanguage.plain;
}

const Set<String> _jsKeywords = {
  'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'debugger', 'default', 'delete', 'do', 'else', 'export', 'extends',
  'finally', 'for', 'from', 'function', 'get', 'if', 'import', 'in',
  'instanceof', 'let', 'new', 'of', 'return', 'set', 'static', 'super',
  'switch', 'this', 'throw', 'try', 'typeof', 'var', 'void', 'while', 'with',
  'yield',
};

const Set<String> _jsLiterals = {
  'true', 'false', 'null', 'undefined', 'NaN', 'Infinity',
};

/// What the tokenizer was in the middle of when a line ended.
enum _State { normal, blockComment, template, htmlComment, htmlTag, htmlScript, htmlStyle }

class _Lexer {
  _Lexer(this.language);

  final SyntaxLanguage language;
  _State state = _State.normal;
  int cssDepth = 0;
  // Inside an HTML tag: what the content after it will be.
  _State afterTag = _State.normal;

  List<Token> line(String text) {
    switch (language) {
      case SyntaxLanguage.javascript:
      case SyntaxLanguage.json:
        final tokens = <Token>[];
        _javascript(text, 0, text.length, tokens);
        return tokens;
      case SyntaxLanguage.css:
        final tokens = <Token>[];
        _css(text, 0, text.length, tokens);
        return tokens;
      case SyntaxLanguage.html:
        return _html(text);
      case SyntaxLanguage.plain:
        return const [];
    }
  }

  static bool _isIdentifierStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24 ||
      c >= 0x80;

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static bool _isIdentifierPart(int c) => _isIdentifierStart(c) || _isDigit(c);

  int _stringEnd(String text, int start, int end, int quote) {
    var i = start;
    while (i < end) {
      final c = text.codeUnitAt(i);
      if (c == 0x5C) {
        i += 2;
        continue;
      }
      if (c == quote) return i + 1;
      i++;
    }
    return end;
  }

  void _javascript(String text, int from, int end, List<Token> tokens) {
    var i = from;
    // The last thing that was not space, to tell a division from a pattern.
    String previous = '';
    while (i < end) {
      if (state == _State.blockComment) {
        final close = text.indexOf('*/', i);
        final stop = close < 0 || close >= end ? end : close + 2;
        tokens.add(Token(i, stop, TokenKind.comment));
        if (close >= 0 && close < end) state = _State.normal;
        i = stop;
        continue;
      }
      if (state == _State.template) {
        var j = i;
        while (j < end && text[j] != '`') {
          if (text[j] == r'\') j++;
          j++;
        }
        if (j < end) {
          j++;
          state = _State.normal;
        }
        j = j.clamp(i, end);
        tokens.add(Token(i, j, TokenKind.string));
        i = j;
        previous = '`';
        continue;
      }
      final c = text.codeUnitAt(i);
      final next = i + 1 < end ? text.codeUnitAt(i + 1) : 0;
      if (c == 0x20 || c == 0x09) {
        i++;
        continue;
      }
      if (c == 0x2F && next == 0x2F) {
        tokens.add(Token(i, end, TokenKind.comment));
        return;
      }
      if (c == 0x2F && next == 0x2A) {
        state = _State.blockComment;
        final close = text.indexOf('*/', i + 2);
        final stop = close < 0 || close >= end ? end : close + 2;
        tokens.add(Token(i, stop, TokenKind.comment));
        if (close >= 0 && close < end) state = _State.normal;
        i = stop;
        continue;
      }
      if (c == 0x22 || c == 0x27) {
        final stop = _stringEnd(text, i + 1, end, c);
        var kind = TokenKind.string;
        if (language == SyntaxLanguage.json) {
          var k = stop;
          while (k < end && text[k] == ' ') {
            k++;
          }
          if (k < end && text[k] == ':') kind = TokenKind.property;
        }
        tokens.add(Token(i, stop, kind));
        i = stop;
        previous = '"';
        continue;
      }
      if (c == 0x60) {
        state = _State.template;
        tokens.add(Token(i, i + 1, TokenKind.string));
        i++;
        continue;
      }
      if (c == 0x2F && _patternCanFollow(previous)) {
        var j = i + 1;
        var inClass = false;
        while (j < end) {
          final d = text[j];
          if (d == r'\') {
            j += 2;
            continue;
          }
          if (d == '[') inClass = true;
          if (d == ']') inClass = false;
          if (d == '/' && !inClass) break;
          j++;
        }
        if (j < end) {
          j++;
          while (j < end && _isIdentifierPart(text.codeUnitAt(j))) {
            j++;
          }
          tokens.add(Token(i, j, TokenKind.regexp));
          i = j;
          previous = '/re';
          continue;
        }
      }
      if (_isDigit(c) || (c == 0x2E && _isDigit(next))) {
        var j = i + 1;
        while (j < end &&
            (_isIdentifierPart(text.codeUnitAt(j)) || text[j] == '.')) {
          j++;
        }
        tokens.add(Token(i, j, TokenKind.number));
        i = j;
        previous = '0';
        continue;
      }
      if (_isIdentifierStart(c)) {
        var j = i + 1;
        while (j < end && _isIdentifierPart(text.codeUnitAt(j))) {
          j++;
        }
        final word = text.substring(i, j);
        var k = j;
        while (k < end && text[k] == ' ') {
          k++;
        }
        final TokenKind kind;
        if (previous != '.' && _jsKeywords.contains(word)) {
          kind = TokenKind.keyword;
        } else if (_jsLiterals.contains(word)) {
          kind = TokenKind.literal;
        } else if (k < end && text[k] == '(' || previous == 'function') {
          kind = TokenKind.function;
        } else if (previous == '.') {
          kind = TokenKind.property;
        } else {
          kind = TokenKind.variable;
        }
        tokens.add(Token(i, j, kind));
        previous = word;
        i = j;
        continue;
      }
      tokens.add(Token(i, i + 1, TokenKind.punctuation));
      previous = text[i];
      i++;
    }
  }

  static bool _patternCanFollow(String previous) {
    if (previous.isEmpty) return true;
    if (const {'return', 'typeof', 'case', 'do', 'else', 'in', 'of', 'void', 'delete', 'throw', 'new'}.contains(previous)) {
      return true;
    }
    return previous.length == 1 && '(,=:[!&|?{};+-*%<>~^'.contains(previous);
  }

  void _css(String text, int from, int end, List<Token> tokens) {
    var i = from;
    var afterColon = false;
    while (i < end) {
      if (state == _State.blockComment) {
        final close = text.indexOf('*/', i);
        final stop = close < 0 || close >= end ? end : close + 2;
        tokens.add(Token(i, stop, TokenKind.comment));
        if (close >= 0 && close < end) state = _State.normal;
        i = stop;
        continue;
      }
      final c = text[i];
      if (c == ' ' || c == '\t') {
        i++;
        continue;
      }
      if (c == '/' && i + 1 < end && text[i + 1] == '*') {
        state = _State.blockComment;
        final close = text.indexOf('*/', i + 2);
        final stop = close < 0 || close >= end ? end : close + 2;
        tokens.add(Token(i, stop, TokenKind.comment));
        if (close >= 0 && close < end) state = _State.normal;
        i = stop;
        continue;
      }
      if (c == '"' || c == "'") {
        final stop = _stringEnd(text, i + 1, end, c.codeUnitAt(0));
        tokens.add(Token(i, stop, TokenKind.string));
        i = stop;
        continue;
      }
      if (c == '{') {
        cssDepth++;
        afterColon = false;
        tokens.add(Token(i, i + 1, TokenKind.punctuation));
        i++;
        continue;
      }
      if (c == '}') {
        if (cssDepth > 0) cssDepth--;
        afterColon = false;
        tokens.add(Token(i, i + 1, TokenKind.punctuation));
        i++;
        continue;
      }
      if (c == ';') {
        afterColon = false;
        tokens.add(Token(i, i + 1, TokenKind.punctuation));
        i++;
        continue;
      }
      if (c == '@') {
        var j = i + 1;
        while (j < end && RegExp(r'[\w-]').hasMatch(text[j])) {
          j++;
        }
        tokens.add(Token(i, j, TokenKind.atRule));
        i = j;
        continue;
      }
      var j = i;
      while (j < end && !' \t{};:,()"\'/'.contains(text[j])) {
        j++;
      }
      if (j == i) {
        if (c == ':' && cssDepth > 0) afterColon = true;
        tokens.add(Token(i, i + 1, TokenKind.punctuation));
        i++;
        continue;
      }
      // What comes before a "{", with no end of a declaration or block in
      // between, is a selector wherever it is.
      final brace = text.indexOf('{', j);
      bool before(String character) {
        final at = text.indexOf(character, j);
        return at >= 0 && at < brace;
      }

      final opensBlock = brace >= 0 && !before(';') && !before('}');
      TokenKind kind;
      if (cssDepth == 0 || opensBlock) {
        kind = TokenKind.selector;
      } else if (!afterColon) {
        kind = TokenKind.property;
      } else if (RegExp(r'^[-+]?\.?\d').hasMatch(text.substring(i, j))) {
        kind = TokenKind.number;
      } else if (text[i] == '#') {
        kind = TokenKind.number;
      } else if (text.substring(i, j).startsWith('--')) {
        kind = TokenKind.variable;
      } else if (j < end && text[j] == '(') {
        kind = TokenKind.function;
      } else {
        kind = TokenKind.literal;
      }
      tokens.add(Token(i, j, kind));
      i = j;
    }
  }

  List<Token> _html(String text) {
    final tokens = <Token>[];
    var i = 0;
    while (i < text.length) {
      switch (state) {
        case _State.htmlComment:
          final close = text.indexOf('-->', i);
          final stop = close < 0 ? text.length : close + 3;
          tokens.add(Token(i, stop, TokenKind.comment));
          if (close >= 0) state = _State.normal;
          i = stop;
        case _State.htmlScript:
        case _State.htmlStyle:
          final isScript = state == _State.htmlScript;
          final close = text.toLowerCase().indexOf(
            isScript ? '</script' : '</style',
            i,
          );
          final stop = close < 0 ? text.length : close;
          final outer = state;
          state = _inner;
          if (isScript) {
            _javascript(text, i, stop, tokens);
          } else {
            _css(text, i, stop, tokens);
          }
          _inner = state;
          if (close < 0) {
            state = outer;
          } else {
            state = _State.normal;
            _inner = _State.normal;
            cssDepth = 0;
          }
          i = stop;
        case _State.htmlTag:
          final c = text[i];
          if (c == ' ' || c == '\t') {
            i++;
          } else if (c == '>' || (c == '/' && i + 1 < text.length && text[i + 1] == '>')) {
            final stop = c == '>' ? i + 1 : i + 2;
            tokens.add(Token(i, stop, TokenKind.tag));
            state = afterTag;
            afterTag = _State.normal;
            i = stop;
          } else if (c == '"' || c == "'") {
            final close = text.indexOf(c, i + 1);
            final stop = close < 0 ? text.length : close + 1;
            tokens.add(Token(i, stop, TokenKind.attributeValue));
            i = stop;
          } else if (c == '=') {
            tokens.add(Token(i, i + 1, TokenKind.punctuation));
            i++;
          } else {
            var j = i + 1;
            while (j < text.length && !' \t=>"\''.contains(text[j])) {
              j++;
            }
            final isValue = tokens.isNotEmpty &&
                tokens.last.kind == TokenKind.punctuation &&
                text.substring(tokens.last.start, tokens.last.end) == '=';
            tokens.add(
              Token(i, j, isValue ? TokenKind.attributeValue : TokenKind.attributeName),
            );
            i = j;
          }
        default:
          final open = text.indexOf('<', i);
          if (open < 0) {
            i = text.length;
            break;
          }
          if (text.startsWith('<!--', open)) {
            state = _State.htmlComment;
            i = open;
            break;
          }
          var j = open + 1;
          if (j < text.length && (text[j] == '/' || text[j] == '!')) j++;
          final nameStart = j;
          while (j < text.length && RegExp(r'[\w:-]').hasMatch(text[j])) {
            j++;
          }
          if (j == nameStart) {
            i = open + 1;
            break;
          }
          final name = text.substring(nameStart, j).toLowerCase();
          tokens.add(Token(open, j, TokenKind.tag));
          if (text[open + 1] != '/') {
            if (name == 'script') afterTag = _State.htmlScript;
            if (name == 'style') afterTag = _State.htmlStyle;
          }
          state = _State.htmlTag;
          i = j;
      }
    }
    return tokens;
  }

  // The state of the script or style inside a document.
  _State _inner = _State.normal;
}

/// The tokens of each of [lines], carrying comments and strings from one line
/// to the next.
List<List<Token>> highlightLines(List<String> lines, SyntaxLanguage language) {
  final lexer = _Lexer(language);
  return [
    for (final line in lines)
      // A line of hundreds of thousands of characters is left plain.
      line.length > 20000 ? const <Token>[] : lexer.line(line),
  ];
}

List<Token> highlightLine(String line, SyntaxLanguage language) =>
    highlightLines([line], language).single;

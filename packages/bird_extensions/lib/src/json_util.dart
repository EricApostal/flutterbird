import 'dart:convert';

/// Removes `//` and `/* */` comments from [source], leaving string literals
/// alone.
///
/// Firefox accepts comments in `manifest.json` (and in `messages.json`), and
/// plenty of published extensions use them, so a plain `jsonDecode` would
/// reject packages Firefox installs without complaint.
String stripJsonComments(String source) {
  final out = StringBuffer();
  var i = 0;
  final length = source.length;

  while (i < length) {
    final char = source[i];

    if (char == '"') {
      // Copy a whole string, honoring escapes, so "http://x" survives.
      out.write(char);
      i++;
      while (i < length) {
        final inner = source[i];
        out.write(inner);
        i++;
        if (inner == r'\' && i < length) {
          out.write(source[i]);
          i++;
        } else if (inner == '"') {
          break;
        }
      }
      continue;
    }

    if (char == '/' && i + 1 < length) {
      final next = source[i + 1];
      if (next == '/') {
        i += 2;
        while (i < length && source[i] != '\n' && source[i] != '\r') {
          i++;
        }
        continue;
      }
      if (next == '*') {
        i += 2;
        while (i + 1 < length && !(source[i] == '*' && source[i + 1] == '/')) {
          i++;
        }
        i = i + 2 < length ? i + 2 : length;
        continue;
      }
    }

    out.write(char);
    i++;
  }

  return out.toString();
}

/// Decodes UTF-8 [bytes] as the JSON of a manifest or message catalog:
/// comments allowed and a leading byte-order mark ignored.
Object? decodeLenientJson(List<int> bytes) {
  var text = utf8.decode(bytes);
  if (text.startsWith('﻿')) text = text.substring(1);
  return jsonDecode(stripJsonComments(text));
}

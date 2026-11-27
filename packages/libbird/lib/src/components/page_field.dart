/// What a page's focused field takes, and so what an on-screen keyboard should
/// be like, worked out as Chrome on Android does from what the page says.
///
/// This knows nothing of the engine or of Flutter.
library;

import 'dart:convert';

enum FieldKeyboard {
  text,
  multiline,
  email,
  url,
  phone,

  /// A number that may have a sign and a fraction.
  signedDecimal,

  /// A number that may have a fraction.
  decimal,

  /// Digits alone.
  digits,

  /// None at all: the page has keys of its own.
  none,
}

/// What the keyboard's enter key is for.
enum FieldAction { done, go, next, previous, search, send, newline }

enum FieldCapitals { none, sentences, words, characters }

class PageField {
  const PageField({
    this.id,
    this.editable = true,
    this.keyboard = FieldKeyboard.text,
    this.action = FieldAction.done,
    this.capitals = FieldCapitals.none,
    this.secret = false,
    this.autocorrect = true,
  });

  /// What is assumed where the engine cannot say which field it is.
  static const PageField unknown = PageField();

  /// Which element of its page this is.
  final int? id;

  /// Whether it can be typed into, which a read-only one cannot.
  final bool editable;
  final FieldKeyboard keyboard;
  final FieldAction action;
  final FieldCapitals capitals;

  /// A password: hidden, and nothing to be learnt from.
  final bool secret;
  final bool autocorrect;

  /// Reads what the engine says of the focused field (`get_focused_field_json`),
  /// or [unknown] where it says nothing that can be read.
  factory PageField.parse(String json) {
    if (json.isEmpty) return unknown;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return unknown;
    }
    if (decoded is! Map) return unknown;

    String text(String key) {
      final value = (decoded as Map)[key];
      return value is String ? value.trim().toLowerCase() : '';
    }

    final tag = text('tag');
    final type = tag == 'input' ? text('type') : '';
    final mode = text('inputmode');
    final secret = type == 'password';
    final takesLines = tag == 'textarea' || tag == 'contenteditable';
    final plain = takesLines ? FieldKeyboard.multiline : FieldKeyboard.text;

    // What the page asks for by name comes before what the type implies.
    final keyboard = switch (mode) {
      'none' => FieldKeyboard.none,
      // A hidden number is still typed as hidden text.
      _ when secret => FieldKeyboard.text,
      'text' || 'search' => plain,
      'email' => FieldKeyboard.email,
      'url' => FieldKeyboard.url,
      'tel' => FieldKeyboard.phone,
      'numeric' => FieldKeyboard.digits,
      'decimal' => FieldKeyboard.decimal,
      _ => switch (type) {
        'email' => FieldKeyboard.email,
        'url' => FieldKeyboard.url,
        'tel' => FieldKeyboard.phone,
        'number' => FieldKeyboard.signedDecimal,
        _ => plain,
      },
    };

    final action = switch (text('enterkeyhint')) {
      'enter' => FieldAction.newline,
      'done' => FieldAction.done,
      'go' => FieldAction.go,
      'next' => FieldAction.next,
      'previous' => FieldAction.previous,
      'search' => FieldAction.search,
      'send' => FieldAction.send,
      _ when takesLines => FieldAction.newline,
      _ when type == 'search' || mode == 'search' => FieldAction.search,
      _ when decoded['hasNext'] == true => FieldAction.next,
      _ when decoded['inForm'] == true => FieldAction.go,
      _ => FieldAction.done,
    };

    // Words are only for what is written in words.
    final written =
        !secret &&
        (keyboard == FieldKeyboard.text ||
            keyboard == FieldKeyboard.multiline) &&
        type != 'email' &&
        type != 'url';
    final capitals = !written
        ? FieldCapitals.none
        : switch (text('autocapitalize')) {
            'off' || 'none' => FieldCapitals.none,
            'characters' => FieldCapitals.characters,
            'words' => FieldCapitals.words,
            _ => FieldCapitals.sentences,
          };

    final id = decoded['id'];
    return PageField(
      id: id is int ? id : null,
      editable: decoded['editable'] != false,
      keyboard: keyboard,
      action: action,
      capitals: capitals,
      secret: secret,
      autocorrect: written && text('autocorrect') != 'off',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PageField &&
      other.id == id &&
      other.editable == editable &&
      other.keyboard == keyboard &&
      other.action == action &&
      other.capitals == capitals &&
      other.secret == secret &&
      other.autocorrect == autocorrect;

  @override
  int get hashCode => Object.hash(
    id,
    editable,
    keyboard,
    action,
    capitals,
    secret,
    autocorrect,
  );
}

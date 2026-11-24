import 'json_util.dart';
import 'zip_reader.dart';

/// A parsed `_locales/<locale>/messages.json`.
class MessageCatalog {
  MessageCatalog(this._messages);

  /// An empty catalog, which leaves every `__MSG_x__` reference untouched.
  static final MessageCatalog empty = MessageCatalog(const {});

  factory MessageCatalog.fromJson(Object? json) {
    final messages = <String, _Message>{};
    if (json is Map) {
      for (final entry in json.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final text = value['message'];
        if (text is! String) continue;

        final placeholders = <String, String>{};
        final rawPlaceholders = value['placeholders'];
        if (rawPlaceholders is Map) {
          for (final placeholder in rawPlaceholders.entries) {
            final content = (placeholder.value is Map)
                ? (placeholder.value as Map)['content']
                : null;
            if (content is String) {
              placeholders[placeholder.key.toString().toLowerCase()] = content;
            }
          }
        }
        // Message names are case-insensitive.
        messages[entry.key.toString().toLowerCase()] = _Message(
          text,
          placeholders,
        );
      }
    }
    return MessageCatalog(messages);
  }

  final Map<String, _Message> _messages;

  bool get isEmpty => _messages.isEmpty;

  /// The catalog as the in-page `browser.i18n` reads it: name (lowercase) to
  /// `{"message": text}`, with each named placeholder already replaced by its
  /// content. What remains in the text is `$1`..`$9` for the caller's
  /// substitutions and `$$` for a literal dollar sign.
  Map<String, Map<String, String>> shimEntries() {
    return {
      for (final entry in _messages.entries)
        entry.key: {'message': entry.value.withPlaceholdersReplaced()},
    };
  }

  /// The message called [name], or null if the catalog has none.
  String? message(String name) {
    final entry = _messages[name.toLowerCase()];
    if (entry == null) return null;
    return entry.expand();
  }

  /// Replaces each `__MSG_name__` in [value] with its message. References
  /// to messages the catalog lacks are left as they were.
  String localize(String value) {
    if (!value.contains('__MSG_')) return value;
    return value.replaceAllMapped(RegExp(r'__MSG_([A-Za-z0-9_@]+?)__'), (
      match,
    ) {
      return message(match.group(1)!) ?? match.group(0)!;
    });
  }
}

class _Message {
  _Message(this.text, this.placeholders);

  final String text;
  final Map<String, String> placeholders;

  /// The text with `$name$` replaced by that placeholder's content, leaving
  /// `$$` and `$1`.. for whoever substitutes arguments.
  String withPlaceholdersReplaced() {
    return text.replaceAllMapped(RegExp(r'\$([A-Za-z0-9_@]+)\$'), (match) {
      return placeholders[match.group(1)!.toLowerCase()] ?? match.group(0)!;
    });
  }

  String expand() {
    return text.replaceAllMapped(RegExp(r'\$([A-Za-z0-9_@]+)\$|\$\$'), (match) {
      if (match.group(0) == r'$$') return r'$';
      return placeholders[match.group(1)!.toLowerCase()] ?? match.group(0)!;
    });
  }
}

/// The locale directories of an extension that [archive] holds.
List<String> availableLocales(ZipArchive archive) {
  final locales = <String>{};
  for (final entry in archive.entries) {
    final match = RegExp(
      r'^_locales/([^/]+)/messages\.json$',
    ).firstMatch(entry.name);
    if (match != null) locales.add(match.group(1)!);
  }
  return locales.toList()..sort();
}

/// Chooses the locale directory to read, as Firefox does: the user's
/// locales first (exact, then language-only), then the extension's default.
String? chooseLocale({
  required List<String> available,
  required List<String> preferred,
  String? defaultLocale,
}) {
  String normalize(String locale) => locale.replaceAll('-', '_').toLowerCase();

  final byNormalized = {for (final name in available) normalize(name): name};

  for (final locale in preferred) {
    final normalized = normalize(locale);
    final exact = byNormalized[normalized];
    if (exact != null) return exact;

    final language = normalized.split('_').first;
    final languageOnly = byNormalized[language];
    if (languageOnly != null) return languageOnly;

    // Neither "en_US" nor plain "en" ships, but "en_GB" does: it is the
    // closest thing to what the user asked for.
    for (final candidate in byNormalized.entries) {
      if (candidate.key.split('_').first == language) return candidate.value;
    }
  }

  if (defaultLocale != null) {
    return byNormalized[normalize(defaultLocale)];
  }
  return null;
}

/// Reads the catalog for [locale] out of [archive].
MessageCatalog readCatalog(ZipArchive archive, String? locale) {
  if (locale == null) return MessageCatalog.empty;
  final entry = archive.find('_locales/$locale/messages.json');
  if (entry == null) return MessageCatalog.empty;

  try {
    return MessageCatalog.fromJson(decodeLenientJson(archive.read(entry)));
  } on FormatException {
    return MessageCatalog.empty;
  }
}

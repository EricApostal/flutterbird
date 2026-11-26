/// What the address bar fills in as the user types, and what it marks in its
/// suggestions.
library;

/// An address filled in after what the user typed.
class InlineCompletion {
  const InlineCompletion({required this.text, required this.target});

  /// The whole of what the field shows: exactly what was typed, then the rest,
  /// which the field shows selected.
  final String text;

  /// Where accepting it goes: a whole address, scheme and all.
  final String target;
}

final RegExp _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');

/// How an address reads in the address bar: without `https://`, `http://` or a
/// leading `www.`, and without the lone slash after a bare host.
String displayAddress(String url) {
  var text = url.trim();
  final web = RegExp(r'^https?://', caseSensitive: false).firstMatch(text);
  if (web == null) return text;
  text = text.substring(web.end);
  if (text.toLowerCase().startsWith('www.')) text = text.substring(4);
  if (text.indexOf('/') == text.length - 1) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// How [url] would complete [typed], or null if [typed] does not begin it.
///
/// While only a host has been typed, only the host is filled in: someone typing
/// `you` means the site, not whichever of its pages was last seen. Once a slash
/// is typed, the rest of the address is.
InlineCompletion? completeInline(String typed, String url) {
  if (typed.isEmpty || typed.contains(RegExp(r'\s'))) return null;

  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  final full = url.trim();
  final afterScheme = full.substring(_scheme.firstMatch(full)?.end ?? 0);

  final lowerTyped = typed.toLowerCase();
  final hasWww = afterScheme.toLowerCase().startsWith('www.');

  // The ways the address could be being typed, shortest first. The `www.` and
  // the scheme count only once they are plainly what is being typed, or an `h`
  // or a `w` would begin every address there is.
  final forms = <String>[
    if (hasWww) afterScheme.substring(4),
    if (!hasWww || lowerTyped.startsWith('www.')) afterScheme,
    if (typed.contains('://')) full,
  ];

  for (final form in forms) {
    if (!form.toLowerCase().startsWith(lowerTyped)) continue;

    final hostStart = _scheme.firstMatch(form)?.end ?? 0;
    final slash = form.indexOf(RegExp(r'[/?#]'), hostStart);
    final hostEnd = slash < 0 ? form.length : slash;

    final String filled;
    final String target;
    if (typed.length <= hostEnd) {
      filled = form.substring(0, hostEnd);
      // A user name before the host would make the address read as one site
      // and go to another.
      if (uri.userInfo.isNotEmpty) return null;
      target = '${uri.origin}/';
    } else {
      filled = slash >= 0 && slash == form.length - 1
          ? form.substring(0, slash)
          : form;
      // What was typed may be the slash that the shown form drops.
      if (filled.length < typed.length) {
        return InlineCompletion(text: typed, target: full);
      }
      target = full;
    }
    return InlineCompletion(
      text: typed + filled.substring(typed.length),
      target: target,
    );
  }
  return null;
}

/// Whether an edit that left [typed] in the field should be completed.
///
/// [previous] is what the user had typed before it. Taking text away must not
/// be answered by putting it back, and neither a caret in the middle nor a word
/// an input method is still composing has anywhere for a completion to go.
bool allowsInlineCompletion({
  required String previous,
  required String typed,
  required bool caretAtEnd,
  required bool composing,
}) {
  if (!caretAtEnd || composing || typed.isEmpty) return false;
  final deleted = typed.length <= previous.length && previous.startsWith(typed);
  return !deleted;
}

/// Suggestions in the order to list them.
class ArrangedSuggestions<T> {
  const ArrangedSuggestions(this.candidates, this.completion);

  final List<T> candidates;

  /// What the first of [candidates] fills into the field, or null when none of
  /// them completes what was typed.
  final InlineCompletion? completion;
}

/// Orders [candidates], which come best first, so that the best one that
/// completes [typed] leads. Each address is listed once.
ArrangedSuggestions<T> arrangeSuggestions<T>(
  String typed,
  Iterable<T> candidates, {
  required String Function(T candidate) urlOf,
  required bool complete,
}) {
  final seen = <String>{};
  final unique = [
    for (final candidate in candidates)
      if (seen.add(urlOf(candidate))) candidate,
  ];

  if (complete) {
    for (var i = 0; i < unique.length; i++) {
      final completion = completeInline(typed, urlOf(unique[i]));
      if (completion == null) continue;
      final lead = unique.removeAt(i);
      return ArrangedSuggestions([lead, ...unique], completion);
    }
  }
  return ArrangedSuggestions(unique, null);
}

/// A part of a text, from [start] up to [end].
typedef TextSpanRange = ({int start, int end});

/// The parts of [text] to set in bold because they are what [query] asked for:
/// all of the query where the text holds it, and otherwise each of its words
/// where it begins a word of the text.
List<TextSpanRange> matchRanges(String text, String query) {
  final haystack = text.toLowerCase();
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty || haystack.length != text.length) return const [];

  final whole = haystack.indexOf(needle);
  if (whole >= 0) return [(start: whole, end: whole + needle.length)];

  final wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);
  bool startsWord(int index) =>
      index == 0 || !wordCharacter.hasMatch(haystack[index - 1]);

  final found = <TextSpanRange>[];
  for (final term in needle.split(RegExp(r'[\s/.?=&:_-]+'))) {
    if (term.isEmpty) continue;
    var from = 0;
    while (true) {
      final at = haystack.indexOf(term, from);
      if (at < 0) break;
      if (startsWord(at)) found.add((start: at, end: at + term.length));
      from = at + 1;
    }
  }
  found.sort((a, b) => a.start.compareTo(b.start));

  final merged = <TextSpanRange>[];
  for (final range in found) {
    if (merged.isNotEmpty && range.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((
        start: last.start,
        end: range.end > last.end ? range.end : last.end,
      ));
    } else {
      merged.add(range);
    }
  }
  return merged;
}

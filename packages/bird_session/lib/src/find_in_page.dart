/// The small rules of finding text in a page.
library;

/// What the find bar shows beside the words searched for, as Chrome does:
/// which match is selected and how many there are.
///
/// [current] counts from zero. [total] is null while it is not known, and
/// then, as with nothing to search for, there is nothing to show.
String findCountLabel({
  required String query,
  required int current,
  required int? total,
}) {
  if (query.isEmpty || total == null || total < 0) return '';
  if (total == 0) return '0/0';
  return '${(current + 1).clamp(1, total)}/$total';
}

/// Whether two addresses are of one loaded page, which a search stays open
/// over: a jump to another part of a page changes only what follows the `#`.
bool isSamePageForFind(String before, String after) {
  String withoutFragment(String url) {
    final hash = url.indexOf('#');
    // `#/` and `#!` are how single-page sites spell a different page.
    if (hash < 0 || hash + 1 == url.length) {
      return hash < 0 ? url : url.substring(0, hash);
    }
    final next = url[hash + 1];
    return next == '/' || next == '!' ? url : url.substring(0, hash);
  }

  return withoutFragment(before) == withoutFragment(after);
}

/// Compares two extension versions the way Mozilla's "toolkit version
/// format" does, which is what decides whether AMO's version is an update.
///
/// A version is dot-separated parts, and each part is read as
/// `<number-a><string-b><number-c><string-d>`. Numbers compare as numbers,
/// and a string compares below the empty string, so `1.0pre1` is older
/// than `1.0`. `*` in a part stands for infinity.
///
/// https://developer.mozilla.org/docs/Mozilla/Toolkit_version_format
int compareVersions(String a, String b) {
  final left = a.split('.');
  final right = b.split('.');
  final length = left.length > right.length ? left.length : right.length;

  for (var i = 0; i < length; i++) {
    final x = _VersionPart.parse(i < left.length ? left[i] : '0');
    final y = _VersionPart.parse(i < right.length ? right[i] : '0');
    final result = x.compareTo(y);
    if (result != 0) return result;
  }
  return 0;
}

class _VersionPart implements Comparable<_VersionPart> {
  _VersionPart(this.numberA, this.stringB, this.numberC, this.stringD);

  final int numberA;
  final String stringB;
  final int numberC;
  final String stringD;

  static final RegExp _pattern = RegExp(
    r'^(-?\d+)?([^\d-][^\d]*)?(-?\d+)?(.*)$',
  );

  factory _VersionPart.parse(String part) {
    if (part == '*') {
      return _VersionPart(0x7FFFFFFF, '', 0, '');
    }

    final match = _pattern.firstMatch(part)!;
    var numberA = int.tryParse(match.group(1) ?? '') ?? 0;
    var stringB = match.group(2) ?? '';

    // "+" means "one more than the number before it", so 1.0+ > 1.0.
    if (stringB.startsWith('+')) {
      numberA += 1;
      stringB = '';
    }

    return _VersionPart(
      numberA,
      stringB,
      int.tryParse(match.group(3) ?? '') ?? 0,
      match.group(4) ?? '',
    );
  }

  @override
  int compareTo(_VersionPart other) {
    final byNumber = numberA.compareTo(other.numberA);
    if (byNumber != 0) return byNumber;

    final byString = _compareStrings(stringB, other.stringB);
    if (byString != 0) return byString;

    final byNumberC = numberC.compareTo(other.numberC);
    if (byNumberC != 0) return byNumberC;

    return _compareStrings(stringD, other.stringD);
  }

  /// An empty string sorts after any other, so that a pre-release suffix
  /// makes a version older.
  static int _compareStrings(String x, String y) {
    if (x.isEmpty && y.isEmpty) return 0;
    if (x.isEmpty) return 1;
    if (y.isEmpty) return -1;
    return x.compareTo(y).sign;
  }
}

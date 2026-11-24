/// WebExtension match patterns and globs.
///
/// https://developer.mozilla.org/docs/Mozilla/Add-ons/WebExtensions/Match_patterns
library;

/// The schemes `<all_urls>` stands for.
const Set<String> allUrlsSchemes = {
  'http',
  'https',
  'ws',
  'wss',
  'ftp',
  'ftps',
  'data',
  'file',
};

/// The schemes the `*` scheme stands for.
const Set<String> wildcardSchemes = {'http', 'https', 'ws', 'wss'};

const Set<String> _explicitSchemes = {
  'http',
  'https',
  'ws',
  'wss',
  'ftp',
  'ftps',
  'file',
};

const Map<String, int> _defaultPorts = {
  'http': 80,
  'https': 443,
  'ws': 80,
  'wss': 443,
  'ftp': 21,
  'ftps': 990,
};

/// One match pattern such as `*://*.example.com/*` or `<all_urls>`.
class MatchPattern {
  MatchPattern._({
    required this.source,
    required Set<String> schemes,
    required this.host,
    required this.matchesSubdomains,
    required this.port,
    required String path,
  }) : _schemes = schemes,
       _path = path;

  /// The pattern as written.
  final String source;

  /// The host to match, lowercase, without any `*.` prefix. Null for any
  /// host (`*`, `<all_urls>`, and the empty host of `file:` patterns).
  final String? host;

  /// True for `*.example.com`, which also matches `example.com` itself.
  final bool matchesSubdomains;

  /// The port to require, or null to accept any port.
  final int? port;

  final Set<String> _schemes;
  final String _path;
  RegExp? _pathExpression;

  /// Parses [pattern], throwing a [FormatException] when it is not valid.
  factory MatchPattern.parse(String pattern) {
    if (pattern == '<all_urls>') {
      return MatchPattern._(
        source: pattern,
        schemes: allUrlsSchemes,
        host: null,
        matchesSubdomains: false,
        port: null,
        path: '*',
      );
    }

    final schemeEnd = pattern.indexOf('://');
    if (schemeEnd <= 0) {
      throw FormatException('Missing scheme in match pattern', pattern);
    }

    final scheme = pattern.substring(0, schemeEnd);
    final Set<String> schemes;
    if (scheme == '*') {
      schemes = wildcardSchemes;
    } else if (_explicitSchemes.contains(scheme)) {
      schemes = {scheme};
    } else {
      throw FormatException('Unsupported scheme "$scheme"', pattern);
    }

    final rest = pattern.substring(schemeEnd + 3);
    final pathStart = rest.indexOf('/');
    if (pathStart < 0) {
      throw FormatException('Missing path in match pattern', pattern);
    }

    final authority = rest.substring(0, pathStart);
    final path = rest.substring(pathStart);

    if (scheme == 'file') {
      // A file: pattern has no host, but Firefox accepts a `*` there, as in
      // `file://*/*`, which extensions such as uBlock Origin use.
      if (authority.isNotEmpty && authority != '*') {
        throw FormatException('file: patterns have no host', pattern);
      }
      return MatchPattern._(
        source: pattern,
        schemes: schemes,
        host: null,
        matchesSubdomains: false,
        port: null,
        path: path,
      );
    }

    if (authority.isEmpty) {
      throw FormatException('Missing host in match pattern', pattern);
    }

    var hostPart = authority;
    int? port;

    final closeBracket = authority.startsWith('[')
        ? authority.indexOf(']')
        : -1;
    if (authority.startsWith('[')) {
      if (closeBracket < 0) {
        throw FormatException('Unterminated IPv6 host', pattern);
      }
      hostPart = authority.substring(0, closeBracket + 1);
      final after = authority.substring(closeBracket + 1);
      if (after.isNotEmpty) {
        if (!after.startsWith(':')) {
          throw FormatException('Unexpected text after host', pattern);
        }
        port = _parsePort(after.substring(1), pattern);
      }
    } else {
      final colon = authority.lastIndexOf(':');
      if (colon >= 0) {
        hostPart = authority.substring(0, colon);
        port = _parsePort(authority.substring(colon + 1), pattern);
      }
    }

    String? host;
    var subdomains = false;

    if (hostPart == '*') {
      host = null;
    } else {
      if (hostPart.startsWith('*.')) {
        subdomains = true;
        hostPart = hostPart.substring(2);
      }
      if (hostPart.isEmpty || hostPart.contains('*')) {
        throw FormatException('Invalid host "$hostPart"', pattern);
      }
      host = hostPart.toLowerCase();
      if (host.startsWith('[')) {
        // Uri.host reports IPv6 addresses without their brackets.
        host = host.substring(1, host.length - 1);
      }
    }

    return MatchPattern._(
      source: pattern,
      schemes: schemes,
      host: host,
      matchesSubdomains: subdomains,
      port: port,
      path: path,
    );
  }

  static MatchPattern? tryParse(String pattern) {
    try {
      return MatchPattern.parse(pattern);
    } on FormatException {
      return null;
    }
  }

  static int? _parsePort(String text, String pattern) {
    if (text == '*') return null;
    final port = int.tryParse(text);
    if (port == null || port < 0 || port > 65535) {
      throw FormatException('Invalid port "$text"', pattern);
    }
    return port;
  }

  /// True when the pattern puts no limit on the host.
  bool get matchesAllHosts =>
      host == null && !_schemes.every((scheme) => scheme == 'file');

  /// True when the pattern grants every website, however it is spelled:
  /// `<all_urls>`, or a wildcard host with any path over http or https.
  /// This is what makes a permission prompt say "all websites".
  bool get isAllUrls =>
      source == '<all_urls>' ||
      (host == null &&
          _path == '/*' &&
          (_schemes.contains('http') || _schemes.contains('https')));

  /// True when every URL that [other] matches is also matched by this one,
  /// which is how a granted host permission is checked against what a content
  /// script asks to run on.
  bool covers(MatchPattern other) {
    if (source == '<all_urls>') {
      return other._schemes.every(allUrlsSchemes.contains);
    }
    if (other.source == '<all_urls>') return false;

    if (!other._schemes.every(_schemes.contains)) return false;

    if (host != null) {
      final otherHost = other.host;
      if (otherHost == null) return false;
      final sameHost = otherHost == host;
      final underSubdomain = matchesSubdomains && otherHost.endsWith('.$host');
      final bothSubdomains = other.matchesSubdomains && matchesSubdomains;
      if (!sameHost && !underSubdomain) return false;
      // example.com does not cover *.example.com.
      if (other.matchesSubdomains && !matchesSubdomains) return false;
      if (sameHost && other.matchesSubdomains && !bothSubdomains) return false;
    }

    if (port != null && port != other.port) return false;

    if (_path == '*' || _path == '/*') return true;
    return _path == other._path;
  }

  bool matches(Uri url) {
    final scheme = url.scheme.toLowerCase();
    if (!_schemes.contains(scheme)) return false;

    if (scheme == 'file') {
      return _matchesPath(url);
    }

    if (host != null && !_matchesHost(url.host.toLowerCase())) return false;

    if (port != null) {
      final actual = url.hasPort ? url.port : _defaultPorts[scheme];
      if (actual != port) return false;
    }

    return _matchesPath(url);
  }

  bool matchesString(String url) {
    final parsed = Uri.tryParse(url);
    return parsed != null && matches(parsed);
  }

  bool _matchesHost(String actual) {
    final expected = host!;
    if (actual == expected) return true;
    return matchesSubdomains && actual.endsWith('.$expected');
  }

  bool _matchesPath(Uri url) {
    if (_path == '*' || _path == '/*') return true;

    var target = url.path.isEmpty ? '/' : url.path;
    if (url.hasQuery) target = '$target?${url.query}';

    return (_pathExpression ??= _globToRegExp(
      _path,
      caseSensitive: true,
    )).hasMatch(target);
  }

  @override
  String toString() => source;
}

/// A set of patterns where any one match is enough.
class MatchPatternSet {
  MatchPatternSet(this.patterns);

  /// Parses [sources], leaving out any that are invalid. The ones that were
  /// dropped are returned through [rejected] when it is given.
  factory MatchPatternSet.parse(
    Iterable<String> sources, {
    List<String>? rejected,
  }) {
    final patterns = <MatchPattern>[];
    for (final source in sources) {
      final pattern = MatchPattern.tryParse(source);
      if (pattern == null) {
        rejected?.add(source);
      } else {
        patterns.add(pattern);
      }
    }
    return MatchPatternSet(patterns);
  }

  final List<MatchPattern> patterns;

  bool get isEmpty => patterns.isEmpty;

  bool matches(Uri url) => patterns.any((pattern) => pattern.matches(url));

  bool matchesString(String url) {
    final parsed = Uri.tryParse(url);
    return parsed != null && matches(parsed);
  }

  /// True when any pattern covers every website.
  bool get coversAllHosts => patterns.any((pattern) => pattern.isAllUrls);
}

/// A `include_globs` / `exclude_globs` entry: `*` matches any run of
/// characters and `?` any single one. Matching is case-insensitive, like
/// Greasemonkey's, which these keys come from.
class UrlGlob {
  UrlGlob(this.source)
    : _expression = _globToRegExp(
        source,
        caseSensitive: false,
        questionMark: true,
      );

  final String source;
  final RegExp _expression;

  bool matches(String url) => _expression.hasMatch(url);
}

RegExp _globToRegExp(
  String glob, {
  required bool caseSensitive,
  bool questionMark = false,
}) {
  final buffer = StringBuffer('^');
  for (final rune in glob.runes) {
    final char = String.fromCharCode(rune);
    if (char == '*') {
      buffer.write('.*');
    } else if (questionMark && char == '?') {
      buffer.write('.');
    } else {
      buffer.write(RegExp.escape(char));
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString(), caseSensitive: caseSensitive, dotAll: true);
}

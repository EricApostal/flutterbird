import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

bool m(String pattern, String url) =>
    MatchPattern.parse(pattern).matchesString(url);

void main() {
  coverageTests();

  group('parsing', () {
    test('accepts valid patterns', () {
      for (final pattern in [
        '<all_urls>',
        '*://*/*',
        'https://*.example.com/*',
        'http://localhost:8080/path/*',
        'http://localhost:*/*',
        'file:///*',
        'https://[::1]/*',
        'wss://example.com/socket',
      ]) {
        expect(MatchPattern.tryParse(pattern), isNotNull, reason: pattern);
      }
    });

    test('rejects invalid patterns', () {
      for (final pattern in [
        '',
        'example.com',
        'https://example.com',
        'ftp2://example.com/*',
        'https://*.*/*',
        'https://exa*mple.com/*',
        'https:///*',
        'file://host/*',
        'http://host:99999/*',
        'http://host:abc/*',
        'javascript://x/*',
      ]) {
        expect(MatchPattern.tryParse(pattern), isNull, reason: pattern);
      }
    });
  });

  group('matching', () {
    test('wildcard scheme covers http, https, ws and wss only', () {
      for (final url in [
        'http://a.com/',
        'https://a.com/',
        'ws://a.com/',
        'wss://a.com/',
      ]) {
        expect(m('*://a.com/*', url), isTrue, reason: url);
      }
      expect(m('*://a.com/*', 'ftp://a.com/'), isFalse);
      expect(m('*://a.com/*', 'file:///a.com/'), isFalse);
    });

    test('subdomain wildcard includes the bare domain, not lookalikes', () {
      expect(m('https://*.example.com/*', 'https://example.com/'), isTrue);
      expect(m('https://*.example.com/*', 'https://a.b.example.com/x'), isTrue);
      expect(m('https://*.example.com/*', 'https://badexample.com/'), isFalse);
      expect(
        m('https://*.example.com/*', 'https://example.com.evil.net/'),
        isFalse,
      );
      expect(m('https://example.com/*', 'https://www.example.com/'), isFalse);
    });

    test('host matching ignores case', () {
      expect(m('https://Example.COM/*', 'https://example.com/'), isTrue);
      expect(m('https://example.com/*', 'HTTPS://EXAMPLE.COM/'), isTrue);
    });

    test('ports', () {
      expect(m('http://localhost/*', 'http://localhost:3000/'), isTrue);
      expect(m('http://localhost:3000/*', 'http://localhost:3000/'), isTrue);
      expect(m('http://localhost:3000/*', 'http://localhost:4000/'), isFalse);
      expect(m('https://a.com:443/*', 'https://a.com/'), isTrue);
      expect(m('http://localhost:*/*', 'http://localhost:9/'), isTrue);
    });

    test('paths and queries', () {
      expect(m('https://a.com/foo/*', 'https://a.com/foo/bar'), isTrue);
      expect(m('https://a.com/foo/*', 'https://a.com/foo'), isFalse);
      expect(m('https://a.com/foo*', 'https://a.com/foo'), isTrue);
      expect(m('https://a.com/*bar', 'https://a.com/x/bar'), isTrue);
      expect(m('https://a.com/page?x=*', 'https://a.com/page?x=1'), isTrue);
      expect(m('https://a.com/page', 'https://a.com/page?x=1'), isFalse);
      expect(m('https://a.com/*', 'https://a.com'), isTrue);
    });

    test('regex metacharacters in a path are literal', () {
      expect(m('https://a.com/a.b/*', 'https://a.com/aXb/c'), isFalse);
      expect(m('https://a.com/a.b/*', 'https://a.com/a.b/c'), isTrue);
    });

    test('<all_urls> covers the permitted schemes only', () {
      expect(m('<all_urls>', 'https://a.com/'), isTrue);
      expect(m('<all_urls>', 'file:///tmp/x.html'), isTrue);
      expect(m('<all_urls>', 'about:blank'), isFalse);
      expect(m('<all_urls>', 'moz-extension://abc/page.html'), isFalse);
    });

    test('file patterns match on path', () {
      expect(m('file:///home/*', 'file:///home/me/doc.html'), isTrue);
      expect(m('file:///home/*', 'file:///etc/passwd'), isFalse);
    });

    test('IPv6 hosts', () {
      expect(m('http://[::1]/*', 'http://[::1]:8080/'), isTrue);
    });
  });

  group('isAllUrls', () {
    test('is true for every spelling of "all websites"', () {
      for (final p in ['<all_urls>', '*://*/*', 'http://*/*', 'https://*/*']) {
        expect(MatchPattern.parse(p).isAllUrls, isTrue, reason: p);
      }
    });

    test('is false for narrower patterns', () {
      for (final p in [
        'https://*/foo',
        'https://*.com/*',
        'file:///*',
        'ws://*/*',
      ]) {
        expect(MatchPattern.parse(p).isAllUrls, isFalse, reason: p);
      }
    });
  });

  group('MatchPatternSet', () {
    test('drops invalid entries and reports them', () {
      final rejected = <String>[];
      final set = MatchPatternSet.parse([
        'https://a.com/*',
        'nonsense',
      ], rejected: rejected);
      expect(set.patterns, hasLength(1));
      expect(rejected, ['nonsense']);
      expect(set.matchesString('https://a.com/x'), isTrue);
      expect(set.matchesString('https://b.com/x'), isFalse);
    });
  });

  group('UrlGlob', () {
    test('supports * and ?, ignoring case', () {
      expect(
        UrlGlob('*://*.example.com/*').matches('https://www.example.com/x'),
        isTrue,
      );
      expect(
        UrlGlob('https://a.com/file?.html').matches('https://a.com/FILE1.HTML'),
        isTrue,
      );
      expect(
        UrlGlob(
          'https://a.com/file?.html',
        ).matches('https://a.com/file12.html'),
        isFalse,
      );
    });
  });
}

void coverageTests() {
  bool covers(String grant, String wanted) =>
      MatchPattern.parse(grant).covers(MatchPattern.parse(wanted));

  group('covers', () {
    test('all urls covers everything it can match', () {
      expect(covers('<all_urls>', 'https://a.com/*'), isTrue);
      expect(covers('<all_urls>', '*://*/*'), isTrue);
      expect(covers('<all_urls>', 'file:///*'), isTrue);
    });

    test('nothing narrower covers all urls', () {
      expect(covers('*://*/*', '<all_urls>'), isFalse);
      expect(covers('https://a.com/*', '<all_urls>'), isFalse);
    });

    test('hosts', () {
      expect(covers('https://a.com/*', 'https://a.com/*'), isTrue);
      expect(covers('https://*.a.com/*', 'https://a.com/*'), isTrue);
      expect(covers('https://*.a.com/*', 'https://x.a.com/*'), isTrue);
      expect(covers('https://*.a.com/*', 'https://*.a.com/*'), isTrue);
      expect(covers('https://*.a.com/*', 'https://*.x.a.com/*'), isTrue);
      expect(covers('https://a.com/*', 'https://x.a.com/*'), isFalse);
      expect(covers('https://a.com/*', 'https://*.a.com/*'), isFalse);
      expect(covers('https://*.a.com/*', 'https://b.com/*'), isFalse);
      expect(covers('https://*.a.com/*', 'https://bada.com/*'), isFalse);
      expect(covers('https://a.com/*', 'https://*/*'), isFalse);
      expect(covers('https://*/*', 'https://a.com/*'), isTrue);
    });

    test('schemes', () {
      expect(covers('*://a.com/*', 'https://a.com/*'), isTrue);
      expect(covers('https://a.com/*', '*://a.com/*'), isFalse);
      expect(covers('https://a.com/*', 'http://a.com/*'), isFalse);
    });

    test('ports and paths', () {
      expect(covers('http://localhost/*', 'http://localhost:3000/*'), isTrue);
      expect(covers('http://localhost:3000/*', 'http://localhost/*'), isFalse);
      expect(covers('https://a.com/*', 'https://a.com/path/*'), isTrue);
      expect(covers('https://a.com/path/*', 'https://a.com/*'), isFalse);
      expect(covers('https://a.com/p', 'https://a.com/p'), isTrue);
    });
  });
}

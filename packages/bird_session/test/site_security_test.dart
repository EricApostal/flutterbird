import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

void main() {
  SiteSecurityKind kind(String url) => SiteSecurity.of(url).kind;

  test('HTTPS and plain HTTP', () {
    expect(kind('https://example.com/a'), SiteSecurityKind.https);
    expect(kind('HTTPS://EXAMPLE.COM'), SiteSecurityKind.https);
    expect(kind('http://example.com'), SiteSecurityKind.insecure);
    expect(SiteSecurity.of('https://sub.example.com:8443/x').host,
        'sub.example.com');
  });

  test('plain HTTP from this computer is not called insecure', () {
    for (final url in [
      'http://localhost:3000',
      'http://app.localhost',
      'http://127.0.0.1/x',
      'http://127.10.0.2',
      'http://[::1]:8080',
    ]) {
      expect(kind(url), SiteSecurityKind.local, reason: url);
    }
  });

  test('a host that only looks like this computer is not it', () {
    for (final url in [
      'http://localhost.example.com',
      'http://127.0.0.1.example.com',
      'http://127.example.com',
      'http://notlocalhost',
      'http://example.com@evil.test',
    ]) {
      expect(kind(url), SiteSecurityKind.insecure, reason: url);
    }
  });

  test('the address of the host is the one after any user name', () {
    expect(SiteSecurity.of('https://bank.test@evil.test/').host, 'evil.test');
  });

  test('pages that crossed no network', () {
    expect(kind('file:///tmp/a.html'), SiteSecurityKind.file);
    expect(kind('moz-extension://abc/popup.html'), SiteSecurityKind.extension);
    for (final url in ['about:blank', 'data:text/plain,hi', '', 'nonsense']) {
      expect(kind(url), SiteSecurityKind.internal, reason: url);
    }
  });
}

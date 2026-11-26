/// What the address bar may say about how a page got here.
enum SiteSecurityKind {
  /// Loaded over HTTPS.
  https,

  /// Loaded over plain HTTP from somewhere else, where it can be read and
  /// changed on the way.
  insecure,

  /// Plain HTTP from this computer, which crosses no network.
  local,

  /// A file on this computer.
  file,

  /// A page of an extension.
  extension,

  /// A page of the browser, or one with no address of its own.
  internal,
}

/// The security of the page at an address.
///
/// It goes by the address alone. The engine does not yet say how a load went,
/// or show its certificate, so [SiteSecurityKind.https] says only that HTTPS
/// was the way in, and nothing built on this may call a page verified.
class SiteSecurity {
  const SiteSecurity(this.kind, this.host);

  factory SiteSecurity.of(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return const SiteSecurity(SiteSecurityKind.internal, '');

    final host = uri.host;
    return switch (uri.scheme) {
      'https' => SiteSecurity(SiteSecurityKind.https, host),
      'http' => SiteSecurity(
        _isLoopback(host) ? SiteSecurityKind.local : SiteSecurityKind.insecure,
        host,
      ),
      'file' => const SiteSecurity(SiteSecurityKind.file, ''),
      'moz-extension' => SiteSecurity(SiteSecurityKind.extension, host),
      _ => const SiteSecurity(SiteSecurityKind.internal, ''),
    };
  }

  final SiteSecurityKind kind;

  /// The host of the address, or empty where it names none worth showing.
  final String host;

  static bool _isLoopback(String host) {
    if (host == 'localhost' || host.endsWith('.localhost') || host == '::1') {
      return true;
    }
    final parts = host.split('.');
    return parts.length == 4 &&
        parts.first == '127' &&
        parts.every((part) {
          final value = int.tryParse(part);
          return value != null && value >= 0 && value <= 255;
        });
  }
}

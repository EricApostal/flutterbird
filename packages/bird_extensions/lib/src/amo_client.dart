import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'http_fetcher.dart';

/// The input could not be understood as an add-on on addons.mozilla.org.
class AmoInputException implements Exception {
  AmoInputException(this.message);

  final String message;

  @override
  String toString() => 'AmoInputException: $message';
}

/// AMO answered, but not with something that can be installed.
class AmoException implements Exception {
  AmoException(this.message);

  final String message;

  @override
  String toString() => 'AmoException: $message';
}

/// How an add-on was named: by its slug, its GUID or its numeric id.
class AmoQuery {
  const AmoQuery(this.key);

  /// What goes after `/addons/addon/` in the API URL.
  final String key;

  /// Reads an AMO page URL, a download URL, a slug, a GUID or an id.
  ///
  /// Accepted forms:
  ///
  ///  * `https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/`
  ///  * `https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/`
  ///  * `ublock-origin`, `uBlock0@raymondhill.net`, `{uuid}` or `607454`
  factory AmoQuery.parse(String input) {
    final text = input.trim();
    if (text.isEmpty) throw AmoInputException('Nothing to look up');

    if (text.startsWith('http://') || text.startsWith('https://')) {
      final uri = Uri.tryParse(text);
      if (uri == null || uri.host != 'addons.mozilla.org') {
        throw AmoInputException('Only addons.mozilla.org links are supported');
      }

      final segments = uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();

      // .../addon/<slug>/...
      final addonIndex = segments.indexOf('addon');
      if (addonIndex >= 0 && addonIndex + 1 < segments.length) {
        return AmoQuery(segments[addonIndex + 1]);
      }

      // .../downloads/latest/<slug>/...
      final latestIndex = segments.indexOf('latest');
      if (latestIndex >= 0 && latestIndex + 1 < segments.length) {
        return AmoQuery(segments[latestIndex + 1]);
      }

      throw AmoInputException('Could not find an add-on name in "$text"');
    }

    if (text.contains(RegExp(r'[\s/?#]'))) {
      throw AmoInputException('"$text" is not an add-on slug, id or GUID');
    }
    return AmoQuery(text);
  }

  Uri get apiUri => Uri.https(
    'addons.mozilla.org',
    '/api/v5/addons/addon/$key/',
    const {'lang': 'en-US'},
  );
}

/// What AMO says about one add-on's current version.
class AmoAddon {
  const AmoAddon({
    required this.id,
    required this.guid,
    required this.slug,
    required this.name,
    required this.type,
    required this.version,
    required this.fileUrl,
    required this.fileHash,
    required this.fileSize,
    this.permissions = const [],
    this.optionalPermissions = const [],
    this.hostPermissions = const [],
    this.iconUrl,
    this.summary,
    this.isDisabled = false,
    this.requiresPayment = false,
  });

  final int id;
  final String guid;
  final String slug;
  final String name;

  /// `extension`, `statictheme`, `dictionary`, `language` or `sitepermission`.
  final String type;
  final String version;
  final Uri fileUrl;

  /// `sha256:<hex>`, as AMO reports it.
  final String? fileHash;
  final int? fileSize;
  final List<String> permissions;
  final List<String> optionalPermissions;
  final List<String> hostPermissions;
  final Uri? iconUrl;
  final String? summary;
  final bool isDisabled;
  final bool requiresPayment;

  /// Where AMO serves files from. A download URL anywhere else is not
  /// something to follow, whatever the API said.
  static const Set<String> trustedFileHosts = {
    'addons.mozilla.org',
    'addons.cdn.mozilla.net',
  };

  factory AmoAddon.fromJson(Object? json) {
    if (json is! Map) throw AmoException('Unexpected response from AMO');

    final current = json['current_version'];
    if (current is! Map) {
      throw AmoException('This add-on has no published version');
    }
    final file = current['file'];
    if (file is! Map) throw AmoException('The current version has no file');

    final url = Uri.tryParse(file['url']?.toString() ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        !trustedFileHosts.contains(url.host)) {
      throw AmoException(
        'AMO returned an untrusted download URL: ${file['url']}',
      );
    }

    List<String> strings(Object? value) => value is List
        ? [
            for (final item in value)
              if (item is String) item,
          ]
        : const [];

    final id = json['id'];
    final guid = json['guid'];
    final slug = json['slug'];
    final version = current['version'];
    if (id is! int ||
        guid is! String ||
        slug is! String ||
        version is! String) {
      throw AmoException('AMO response is missing id, guid, slug or version');
    }

    final size = file['size'];
    final icon = json['icon_url'];

    return AmoAddon(
      id: id,
      guid: guid,
      slug: slug,
      name: _localized(json['name'], json['default_locale']) ?? slug,
      type: json['type']?.toString() ?? 'extension',
      version: version,
      fileUrl: url,
      fileHash: file['hash'] is String ? file['hash'] as String : null,
      fileSize: size is int ? size : null,
      permissions: strings(file['permissions']),
      optionalPermissions: strings(file['optional_permissions']),
      hostPermissions: strings(file['host_permissions']),
      iconUrl: icon is String ? Uri.tryParse(icon) : null,
      summary: _localized(json['summary'], json['default_locale']),
      isDisabled: json['is_disabled'] == true,
      requiresPayment: json['requires_payment'] == true,
    );
  }

  /// AMO localizes text as a locale → string map, or a plain string when a
  /// single `lang` was asked for.
  static String? _localized(Object? value, Object? defaultLocale) {
    if (value is String) return value;
    if (value is! Map || value.isEmpty) return null;

    for (final locale in [defaultLocale, 'en-US']) {
      final text = value[locale];
      if (text is String) return text;
    }
    final first = value.values.whereType<String>();
    return first.isEmpty ? null : first.first;
  }
}

/// Looks add-ons up on addons.mozilla.org and downloads their files.
class AmoClient {
  AmoClient(this._fetcher);

  final HttpFetcher _fetcher;

  /// The largest package this will download. AMO caps uploads well below
  /// this.
  static const int maxPackageBytes = 200 * 1024 * 1024;

  Future<AmoAddon> lookup(String input) async {
    final query = AmoQuery.parse(input);
    final Object? json;
    try {
      json = await _fetcher.getJson(query.apiUri);
    } on FetchException catch (error) {
      // AMO answers 401 or 403 for an add-on that exists but is not public
      // (unlisted, awaiting review, or deleted), which is no use to install.
      final status = error.statusCode;
      if (status == 404) {
        throw AmoException('"$input" is not on addons.mozilla.org');
      }
      if (status == 401 || status == 403) {
        throw AmoException(
          '"$input" is not publicly available on addons.mozilla.org',
        );
      }
      rethrow;
    }

    final addon = AmoAddon.fromJson(json);
    if (addon.isDisabled) {
      throw AmoException('${addon.name} has been disabled on AMO');
    }
    return addon;
  }

  /// Downloads the file of [addon] and checks it against the hash AMO
  /// published, which catches a corrupted or truncated download. It is not a
  /// signature check; the connection to AMO is what is trusted.
  Future<Uint8List> download(
    AmoAddon addon, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final limit = addon.fileSize != null && addon.fileSize! < maxPackageBytes
        ? addon.fileSize! + 1024
        : maxPackageBytes;

    final bytes = await _fetcher.getBytes(
      addon.fileUrl,
      maxBytes: limit,
      onProgress: onProgress,
    );

    final expected = addon.fileHash;
    if (expected != null) {
      final separator = expected.indexOf(':');
      final algorithm = separator < 0
          ? 'sha256'
          : expected.substring(0, separator);
      final digest = separator < 0
          ? expected
          : expected.substring(separator + 1);

      if (algorithm != 'sha256') {
        throw AmoException('AMO used an unsupported hash ($algorithm)');
      }

      final actual = sha256.convert(bytes).toString();
      if (actual != digest.toLowerCase()) {
        throw AmoException(
          'The download of ${addon.name} does not match the hash AMO published',
        );
      }
    }
    return bytes;
  }
}

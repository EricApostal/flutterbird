import 'dart:convert';
import 'dart:typed_data';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:crypto/crypto.dart';

import 'zip_builder.dart';

/// An in-memory stand-in for addons.mozilla.org.
class FakeAmo implements HttpFetcher {
  final Map<String, Object?> _json = {};
  final Map<String, Uint8List> _files = {};
  final List<Uri> requests = [];

  /// Publishes [files] as `<slug>` at [version]. Returns the xpi bytes.
  Uint8List publish({
    required String slug,
    required String guid,
    required String version,
    required List<ZipItem> files,
    String type = 'extension',
    String? hashOverride,
    Uri? fileUrlOverride,
    int addonId = 1000,
  }) {
    final xpi = buildZip(files);
    final fileUrl =
        fileUrlOverride ??
        Uri.https(
          'addons.mozilla.org',
          '/firefox/downloads/file/$addonId/$slug-$version.xpi',
        );
    final response = <String, Object?>{
      'id': addonId,
      'guid': guid,
      'slug': slug,
      'type': type,
      'default_locale': 'en-US',
      'name': {'en-US': 'Name of $slug'},
      'summary': {'en-US': 'Summary'},
      'is_disabled': false,
      'requires_payment': false,
      'icon_url': 'https://addons.mozilla.org/icon.png',
      'current_version': {
        'version': version,
        'file': {
          'url': fileUrl.toString(),
          'hash': hashOverride ?? 'sha256:${sha256.convert(xpi)}',
          'size': xpi.length,
          'permissions': <String>[],
        },
      },
    };

    final apiUrl = AmoQuery(slug).apiUri;
    _json[apiUrl.toString()] = response;
    _json[AmoQuery(guid).apiUri.toString()] = response;
    _files[fileUrl.toString()] = xpi;
    return xpi;
  }

  @override
  Future<Object?> getJson(Uri url) async {
    requests.add(url);
    final found = _json[url.toString()];
    if (found == null) throw FetchException('not found', statusCode: 404);
    return jsonDecode(jsonEncode(found));
  }

  @override
  Future<Uint8List> getBytes(
    Uri url, {
    required int maxBytes,
    void Function(int received, int? total)? onProgress,
  }) async {
    requests.add(url);
    final found = _files[url.toString()];
    if (found == null) throw FetchException('not found', statusCode: 404);
    if (found.length > maxBytes) throw FetchException('too large');
    onProgress?.call(found.length, found.length);
    return found;
  }
}

/// A minimal valid extension package.
List<ZipItem> sampleExtension({
  String id = 'sample@test',
  String version = '1.0',
  List<String> permissions = const ['storage'],
  String name = '__MSG_extName__',
  List<ZipItem> extra = const [],
}) {
  final manifest = {
    'manifest_version': 2,
    'name': name,
    'version': version,
    'default_locale': 'en',
    'browser_specific_settings': {
      'gecko': {'id': id},
    },
    'permissions': permissions,
    'background': {
      'scripts': ['background.js'],
    },
    'content_scripts': [
      {
        'matches': ['https://example.com/*'],
        'js': ['content.js'],
      },
    ],
    'icons': {'48': 'icon.png'},
  };

  return [
    ZipItem.text('manifest.json', jsonEncode(manifest)),
    ZipItem.text('background.js', '// bg v$version'),
    ZipItem.text('content.js', '// content'),
    ZipItem('icon.png', [0x89, 0x50, 0x4e, 0x47]),
    ZipItem.text(
      '_locales/en/messages.json',
      jsonEncode({
        'extName': {'message': 'Sample Extension'},
      }),
    ),
    ZipItem.text('META-INF/mozilla.rsa', 'sig'),
    ...extra,
  ];
}

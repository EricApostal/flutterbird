import 'dart:typed_data';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

import 'support/fake_amo.dart';

void main() {
  group('AmoQuery.parse', () {
    test('reads page URLs in their usual forms', () {
      for (final url in [
        'https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/',
        'https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/reviews/',
        'https://addons.mozilla.org/firefox/addon/ublock-origin',
        'https://addons.mozilla.org/en-US/android/addon/ublock-origin/?src=search',
        'https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/addon-607454-latest.xpi',
      ]) {
        expect(AmoQuery.parse(url).key, 'ublock-origin', reason: url);
      }
    });

    test('accepts slugs, GUIDs and ids as they are', () {
      expect(AmoQuery.parse('ublock-origin').key, 'ublock-origin');
      expect(
        AmoQuery.parse(' uBlock0@raymondhill.net ').key,
        'uBlock0@raymondhill.net',
      );
      expect(
        AmoQuery.parse('{d634138d-c276-4fc8-924b-40a0ea21d284}').key,
        '{d634138d-c276-4fc8-924b-40a0ea21d284}',
      );
      expect(AmoQuery.parse('607454').key, '607454');
    });

    test('rejects other sites and junk', () {
      for (final input in [
        '',
        '   ',
        'https://evil.example/addon/foo/',
        'https://addons.mozilla.org.evil.example/addon/foo/',
        'https://addons.mozilla.org/en-US/firefox/',
        'a/b',
        'a b',
        'foo?x=1',
      ]) {
        expect(
          () => AmoQuery.parse(input),
          throwsA(isA<AmoInputException>()),
          reason: input,
        );
      }
    });

    test('builds an https API URL', () {
      final uri = AmoQuery.parse('uBlock0@raymondhill.net').apiUri;
      expect(uri.scheme, 'https');
      expect(uri.host, 'addons.mozilla.org');
      expect(uri.path, startsWith('/api/v5/addons/addon/'));
    });
  });

  group('AmoClient', () {
    test('looks an add-on up and verifies the download hash', () async {
      final amo = FakeAmo()
        ..publish(
          slug: 's',
          guid: 's@t',
          version: '1.0',
          files: sampleExtension(),
        );
      final client = AmoClient(amo);

      final addon = await client.lookup('s');
      expect(addon.guid, 's@t');
      expect(addon.version, '1.0');
      expect(addon.name, 'Name of s');

      final bytes = await client.download(addon);
      expect(ZipArchive.fromBytes(bytes).find('manifest.json'), isNotNull);
    });

    test('rejects a download that does not match the published hash', () async {
      final amo = FakeAmo()
        ..publish(
          slug: 's',
          guid: 's@t',
          version: '1.0',
          files: sampleExtension(),
          hashOverride: 'sha256:${'0' * 64}',
        );
      final client = AmoClient(amo);
      final addon = await client.lookup('s');

      await expectLater(client.download(addon), throwsA(isA<AmoException>()));
    });

    test('rejects a download URL outside AMO', () async {
      final amo = FakeAmo()
        ..publish(
          slug: 's',
          guid: 's@t',
          version: '1.0',
          files: sampleExtension(),
          fileUrlOverride: Uri.https('evil.example', '/s.xpi'),
        );
      await expectLater(
        AmoClient(amo).lookup('s'),
        throwsA(isA<AmoException>()),
      );
    });

    test('rejects a plain-http download URL', () async {
      final amo = FakeAmo()
        ..publish(
          slug: 's',
          guid: 's@t',
          version: '1.0',
          files: sampleExtension(),
          fileUrlOverride: Uri.http('addons.mozilla.org', '/s.xpi'),
        );
      await expectLater(
        AmoClient(amo).lookup('s'),
        throwsA(isA<AmoException>()),
      );
    });

    test('treats a non-public add-on (401/403) as unavailable', () async {
      for (final status in [401, 403]) {
        final client = AmoClient(_StatusFetcher(status));
        await expectLater(
          client.lookup('hidden'),
          throwsA(
            isA<AmoException>().having(
              (e) => e.message,
              'message',
              contains('not publicly available'),
            ),
          ),
        );
      }
    });

    test('reports an unknown add-on plainly', () async {
      await expectLater(
        AmoClient(FakeAmo()).lookup('nope'),
        throwsA(
          isA<AmoException>().having(
            (e) => e.message,
            'message',
            contains('not on addons.mozilla.org'),
          ),
        ),
      );
    });
  });
}

class _StatusFetcher implements HttpFetcher {
  _StatusFetcher(this.status);

  final int status;

  @override
  Future<Object?> getJson(Uri url) async =>
      throw FetchException('HTTP $status', statusCode: status);

  @override
  Future<Uint8List> getBytes(
    Uri url, {
    required int maxBytes,
    void Function(int received, int? total)? onProgress,
  }) async => throw FetchException('HTTP $status', statusCode: status);
}

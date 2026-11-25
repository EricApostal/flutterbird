import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

import 'support/fake_amo.dart';
import 'support/zip_builder.dart';

void main() {
  late Directory temp;
  late FakeAmo amo;
  late ExtensionRegistry registry;
  late ExtensionInstaller installer;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bird_install_');
    amo = FakeAmo();
    registry = await ExtensionRegistry.open(
      Directory('${temp.path}/extensions'),
    );
    installer = ExtensionInstaller(registry: registry, amo: AmoClient(amo));
  });

  tearDown(() async {
    await registry.dispose();
    await temp.delete(recursive: true);
  });

  List<String> stagingLeftovers() {
    final installed = Directory('${registry.root.path}/installed');
    if (!installed.existsSync()) return const [];
    return [
      for (final entity in installed.listSync())
        if (entity.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('.'))
          entity.path,
    ];
  }

  group('install', () {
    test('installs an add-on that asks for payment inside itself', () async {
      // AMO flags a password manager or a VPN this way. Downloading it is
      // free, and Firefox installs it like any other.
      amo.publish(
        slug: 'paid',
        guid: 'paid@test',
        version: '1.0',
        files: sampleExtension(id: 'paid@test'),
        requiresPayment: true,
      );

      final result = await installer.installFromAmo('paid');
      expect(result.extension.id, 'paid@test');
    });

    test('downloads, unpacks and records an extension', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );

      final result = await installer.installFromAmo('sample');

      final ext = result.extension;
      expect(ext.id, 'sample@test');
      expect(ext.name, 'Sample Extension', reason: 'name is stored localized');
      expect(ext.version, '1.0');
      expect(ext.enabled, isTrue);
      expect(ext.iconPath, 'icon.png');
      expect(ext.source.isAmo, isTrue);
      expect(ext.source.slug, 'sample');
      expect(ext.origin, 'moz-extension://${ext.uuid}');
      expect(ext.grantedPermissions, ['storage']);
      expect(ext.grantedOrigins, [
        'https://example.com/*',
      ], reason: 'MV2 grants content script hosts');
      expect(result.wasUpdate, isFalse);
      expect(result.warnings, isEmpty);

      final dir = registry.directoryFor(ext);
      expect(File('${dir.path}/manifest.json').existsSync(), isTrue);
      expect(
        File('${dir.path}/background.js').readAsStringSync(),
        '// bg v1.0',
      );
      expect(Directory('${dir.path}/META-INF').existsSync(), isFalse);
      expect(registry.byId('sample@test'), isNotNull);
      expect(stagingLeftovers(), isEmpty);
    });

    test('accepts the AMO URL form', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );
      final result = await installer.installFromAmo(
        'https://addons.mozilla.org/en-US/firefox/addon/sample/',
      );
      expect(result.extension.id, 'sample@test');
    });

    test('persists across a restart', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );
      final installed = (await installer.installFromAmo('sample')).extension;
      await registry.dispose();

      registry = await ExtensionRegistry.open(
        Directory('${temp.path}/extensions'),
      );
      final reloaded = registry.byId('sample@test')!;
      expect(reloaded.uuid, installed.uuid);
      expect(reloaded.name, installed.name);
      expect(reloaded.installedAt, installed.installedAt);
    });

    test('shows the user what it asks for before writing anything', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(
          permissions: ['tabs', 'storage', 'https://*.shop.example/*'],
        ),
      );

      InstallPrompt? seen;
      await installer.installFromAmo(
        'sample',
        onPrompt: (prompt) async {
          seen = prompt;
          expect(
            registry.extensions,
            isEmpty,
            reason: 'nothing recorded until approved',
          );
          return true;
        },
      );

      expect(seen!.name, 'Sample Extension');
      expect(seen!.isUpdate, isFalse);
      expect(seen!.permissions.apiLines, ['Access browser tabs']);
      expect(seen!.permissions.hostLines, [
        'Access your data for sites in the shop.example domain',
        'Access your data for example.com',
      ]);
    });

    test('leaves nothing behind when the user declines', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );

      await expectLater(
        installer.installFromAmo('sample', onPrompt: (_) async => false),
        throwsA(isA<InstallCancelled>()),
      );

      expect(registry.extensions, isEmpty);
      expect(stagingLeftovers(), isEmpty);
      final installed = Directory('${registry.root.path}/installed');
      expect(
        !installed.existsSync() || installed.listSync().isEmpty,
        isTrue,
        reason: 'no directory was created for a declined install',
      );
    });

    test('refuses a tampered download', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
        hashOverride: 'sha256:${'a' * 64}',
      );
      await expectLater(
        installer.installFromAmo('sample'),
        throwsA(isA<AmoException>()),
      );
      expect(registry.extensions, isEmpty);
    });

    test('refuses a package whose id disagrees with AMO', () async {
      amo.publish(
        slug: 'sample',
        guid: 'listed@test',
        version: '1.0',
        files: sampleExtension(id: 'different@test'),
      );
      await expectLater(
        installer.installFromAmo('sample'),
        throwsA(
          isA<InstallException>().having(
            (e) => e.message,
            'message',
            contains('different@test'),
          ),
        ),
      );
      expect(registry.extensions, isEmpty);
    });

    test('refuses themes and other non-extensions', () async {
      amo.publish(
        slug: 'theme',
        guid: 'theme@test',
        version: '1.0',
        files: sampleExtension(),
        type: 'statictheme',
      );
      await expectLater(
        installer.installFromAmo('theme'),
        throwsA(isA<InstallException>()),
      );

      final themeManifest = jsonEncode({
        'manifest_version': 2,
        'name': 'T',
        'version': '1',
        'theme': <String, Object?>{},
      });
      await expectLater(
        installer.installFromBytes(
          buildZip([ZipItem.text('manifest.json', themeManifest)]),
        ),
        throwsA(isA<InstallException>()),
      );
    });

    test(
      'refuses a package that tries to write outside its directory',
      () async {
        amo.publish(
          slug: 'evil',
          guid: 'sample@test',
          version: '1.0',
          files: sampleExtension(
            extra: [ZipItem.text('../../escaped.txt', 'pwned')],
          ),
        );

        await expectLater(
          installer.installFromAmo('evil'),
          throwsA(isA<InstallException>()),
        );

        expect(File('${temp.path}/escaped.txt').existsSync(), isFalse);
        expect(File('${registry.root.path}/escaped.txt').existsSync(), isFalse);
        expect(registry.extensions, isEmpty);
        expect(stagingLeftovers(), isEmpty);
      },
    );

    test('rejects things that are not extensions at all', () async {
      await expectLater(
        installer.installFromBytes(
          buildZip([ZipItem.text('readme.txt', 'hi')]),
        ),
        throwsA(
          isA<InstallException>().having(
            (e) => e.message,
            'message',
            contains('manifest.json'),
          ),
        ),
      );
      await expectLater(
        installer.installFromBytes(
          Uint8List.fromList(utf8.encode('definitely not a zip, just text')),
        ),
        throwsA(isA<InstallException>()),
      );
    });

    test('reports manifest references to files that are missing', () async {
      final files = sampleExtension()
        ..removeWhere((f) => f.name == 'content.js');
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: files,
      );

      final result = await installer.installFromAmo('sample');
      expect(result.warnings, contains(contains('content.js')));
    });

    test('gives a local file without an id a generated one', () async {
      final manifest = jsonEncode({
        'manifest_version': 2,
        'name': 'Local',
        'version': '1',
      });
      final result = await installer.installFromBytes(
        buildZip([ZipItem.text('manifest.json', manifest)]),
      );
      expect(result.extension.id, endsWith('@local.flutterbird'));
      expect(result.extension.source.kind, 'file');
    });
  });

  group('install from a directory', () {
    test('installs an unpacked extension like a package', () async {
      final source = Directory('${temp.path}/unpacked')..createSync();
      File('${source.path}/manifest.json').writeAsStringSync(
        jsonEncode({
          'manifest_version': 2,
          'name': 'Unpacked',
          'version': '0.1',
          'browser_specific_settings': {
            'gecko': {'id': 'unpacked@test'},
          },
          'content_scripts': [
            {
              'matches': ['https://example.com/*'],
              'js': ['js/c.js'],
            },
          ],
        }),
      );
      Directory('${source.path}/js').createSync();
      File('${source.path}/js/c.js').writeAsStringSync('// c');
      Directory('${source.path}/.git').createSync();
      File('${source.path}/.git/config').writeAsStringSync('ignored');
      File('${source.path}/.DS_Store').writeAsStringSync('ignored');

      final result = await installer.installFromDirectory(source);

      expect(result.extension.id, 'unpacked@test');
      expect(result.extension.source.kind, 'file');
      expect(result.warnings, isEmpty);

      final dir = registry.directoryFor(result.extension);
      expect(File('${dir.path}/js/c.js').readAsStringSync(), '// c');
      expect(Directory('${dir.path}/.git').existsSync(), isFalse);
      expect(File('${dir.path}/.DS_Store').existsSync(), isFalse);
    });

    test('reinstalling the same folder updates it in place', () async {
      final source = Directory('${temp.path}/unpacked')..createSync();
      void write(String version) =>
          File('${source.path}/manifest.json').writeAsStringSync(
            jsonEncode({
              'manifest_version': 2,
              'name': 'Unpacked',
              'version': version,
              'browser_specific_settings': {
                'gecko': {'id': 'unpacked@test'},
              },
            }),
          );

      write('1');
      final first = (await installer.installFromDirectory(source)).extension;
      write('2');
      final second = await installer.installFromDirectory(source);

      expect(second.wasUpdate, isTrue);
      expect(second.extension.uuid, first.uuid);
      expect(second.extension.version, '2');
    });

    test('rejects a folder with no manifest', () async {
      final empty = Directory('${temp.path}/empty')..createSync();
      await expectLater(
        installer.installFromDirectory(empty),
        throwsA(isA<InstallException>()),
      );
    });
  });

  group('update', () {
    test('keeps the uuid and replaces the files', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );
      final first = (await installer.installFromAmo('sample')).extension;

      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.1',
        files: sampleExtension(version: '1.1'),
      );
      final result = await installer.update('sample@test');

      expect(result, isNotNull);
      expect(result!.wasUpdate, isTrue);
      expect(result.extension.uuid, first.uuid);
      expect(result.extension.version, '1.1');
      expect(result.extension.installedAt, first.installedAt);
      expect(
        File(
          '${registry.directoryFor(result.extension).path}/background.js',
        ).readAsStringSync(),
        '// bg v1.1',
      );
      expect(registry.extensions, hasLength(1));
      expect(
        Directory(
          '${registry.root.path}/installed',
        ).listSync().whereType<Directory>(),
        hasLength(1),
        reason: 'the old version is cleaned up',
      );
    });

    test('does nothing when already current', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );
      await installer.installFromAmo('sample');
      expect(await installer.update('sample@test'), isNull);
    });

    test('does not downgrade', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '2.0',
        files: sampleExtension(version: '2.0'),
      );
      await installer.installFromAmo('sample');
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.5',
        files: sampleExtension(version: '1.5'),
      );
      expect(await installer.update('sample@test'), isNull);
    });

    test(
      'prompts only for what is new, and not at all when nothing is',
      () async {
        amo.publish(
          slug: 'sample',
          guid: 'sample@test',
          version: '1.0',
          files: sampleExtension(permissions: ['tabs']),
        );
        await installer.installFromAmo('sample');

        amo.publish(
          slug: 'sample',
          guid: 'sample@test',
          version: '1.1',
          files: sampleExtension(version: '1.1', permissions: ['tabs']),
        );
        var prompted = false;
        await installer.update(
          'sample@test',
          onPrompt: (_) async => prompted = true,
        );
        expect(prompted, isFalse, reason: 'same permissions: no interruption');

        amo.publish(
          slug: 'sample',
          guid: 'sample@test',
          version: '1.2',
          files: sampleExtension(
            version: '1.2',
            permissions: ['tabs', 'history'],
          ),
        );
        InstallPrompt? seen;
        await installer.update(
          'sample@test',
          onPrompt: (prompt) async {
            seen = prompt;
            return true;
          },
        );
        expect(seen!.isUpdate, isTrue);
        expect(seen!.permissions.apiLines, [
          'Access browsing history',
        ], reason: 'only the addition');
      },
    );

    test('a declined update keeps the old version intact', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(permissions: ['tabs']),
      );
      final first = (await installer.installFromAmo('sample')).extension;

      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.1',
        files: sampleExtension(
          version: '1.1',
          permissions: ['tabs', 'history'],
        ),
      );
      await expectLater(
        installer.update('sample@test', onPrompt: (_) async => false),
        throwsA(isA<InstallCancelled>()),
      );

      expect(registry.byId('sample@test')!.version, '1.0');
      expect(
        File(
          '${registry.directoryFor(first).path}/background.js',
        ).readAsStringSync(),
        '// bg v1.0',
      );
      expect(stagingLeftovers(), isEmpty);
    });

    test('preserves a disabled extension as disabled', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );
      await installer.installFromAmo('sample');
      await registry.setEnabled('sample@test', enabled: false);

      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.1',
        files: sampleExtension(version: '1.1'),
      );
      final result = await installer.update('sample@test');
      expect(result!.extension.enabled, isFalse);
    });
  });

  group('registry', () {
    test('uninstall removes the files and the record', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );
      final ext = (await installer.installFromAmo('sample')).extension;
      final dir = registry.directoryFor(ext);
      expect(dir.existsSync(), isTrue);

      await installer.uninstall('sample@test');

      expect(dir.existsSync(), isFalse);
      expect(registry.byId('sample@test'), isNull);
      await installer.uninstall('sample@test');
    });

    test('announces changes', () async {
      final events = <RegistryChangeKind>[];
      final subscription = registry.changes.listen(
        (change) => events.add(change.kind),
      );

      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );
      await installer.installFromAmo('sample');
      await registry.setEnabled('sample@test', enabled: false);
      await installer.uninstall('sample@test');
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(events, [
        RegistryChangeKind.added,
        RegistryChangeKind.updated,
        RegistryChangeKind.removed,
      ]);
    });

    test('sets a corrupt registry aside instead of failing to open', () async {
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.0',
        files: sampleExtension(),
      );
      await installer.installFromAmo('sample');
      await registry.dispose();

      File(
        '${temp.path}/extensions/registry.json',
      ).writeAsStringSync('{ this is not json');
      registry = await ExtensionRegistry.open(
        Directory('${temp.path}/extensions'),
      );

      expect(registry.extensions, isEmpty);
      final aside = Directory('${temp.path}/extensions')
          .listSync()
          .map((e) => e.path)
          .where((p) => p.contains('registry.json.corrupt-'));
      expect(aside, hasLength(1));
    });

    test('two installs get different uuids', () {
      expect(ExtensionRegistry.newUuid(), isNot(ExtensionRegistry.newUuid()));
      expect(
        ExtensionRegistry.newUuid(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });
}

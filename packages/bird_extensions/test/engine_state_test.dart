import 'dart:convert';
import 'dart:io';

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
    temp = await Directory.systemTemp.createTemp('bird_state_');
    amo = FakeAmo();
    registry = await ExtensionRegistry.open(Directory('${temp.path}/ext'));
    installer = ExtensionInstaller(registry: registry, amo: AmoClient(amo));
  });

  tearDown(() async {
    await registry.dispose();
    await temp.delete(recursive: true);
  });

  Future<Map<String, Object?>> state() async =>
      jsonDecode(await EngineStateBuilder(registry: registry).build())
          as Map<String, Object?>;

  List<ZipItem> extension({
    int manifestVersion = 2,
    Map<String, Object?> extraManifest = const {},
    List<Map<String, Object?>>? contentScripts,
  }) {
    final manifest = <String, Object?>{
      'manifest_version': manifestVersion,
      'name': '__MSG_name__',
      'version': '1.0',
      'default_locale': 'en',
      'browser_specific_settings': {
        'gecko': {'id': 'sample@test'},
      },
      'content_scripts':
          contentScripts ??
          [
            {
              'matches': ['https://example.com/*'],
              'exclude_matches': ['https://example.com/skip/*'],
              'js': ['a.js', 'missing.js'],
              'css': ['a.css'],
              'run_at': 'document_start',
              'all_frames': true,
            },
          ],
      ...extraManifest,
    };
    return [
      ZipItem.text('manifest.json', jsonEncode(manifest)),
      ZipItem.text('a.js', 'console.log("a")'),
      ZipItem.text('a.css', 'body { color: red }'),
      ZipItem.text(
        '_locales/en/messages.json',
        jsonEncode({
          'name': {'message': 'Sample'},
          'hi': {
            'message': r'Hi $who$',
            'placeholders': {
              'who': {'content': r'$1'},
            },
          },
        }),
      ),
    ];
  }

  test('describes an extension for the engine', () async {
    amo.publish(
      slug: 's',
      guid: 'sample@test',
      version: '1.0',
      files: extension(),
    );
    final installed = (await installer.installFromAmo('s')).extension;

    final built = await state();
    expect(built['shim'], browserShimSource);

    final entry = (built['extensions']! as List).single as Map<String, Object?>;
    expect(entry['uuid'], installed.uuid);
    expect(entry['id'], 'sample@test');
    // What its own pages may read from without CORS.
    expect(entry['hostPermissions'], installed.grantedOrigins);
    expect(entry['hostPermissions'], isNotEmpty);

    final script =
        (entry['contentScripts']! as List).single as Map<String, Object?>;
    expect(script['matches'], ['https://example.com/*']);
    expect(script['excludeMatches'], ['https://example.com/skip/*']);
    expect(script['runAt'], 'document_start');
    expect(script['allFrames'], isTrue);
    expect(script['world'], 'ISOLATED');
    expect(script['js'], [
      {'path': 'a.js', 'source': 'console.log("a")'},
    ], reason: 'a file the package lacks is left out');
    expect(script['css'], [
      {'path': 'a.css', 'source': 'body { color: red }'},
    ]);

    // init is a string of JSON because the engine pastes it into the page.
    final init = jsonDecode(entry['init']! as String) as Map<String, Object?>;
    expect(init['id'], 'sample@test');
    expect(init['baseUrl'], '${installed.origin}/');
    expect(init['contextType'], 'content_script');
    expect((init['manifest']! as Map)['name'], 'Sample', reason: 'localized');
    expect((init['messages']! as Map)['hi'], {'message': r'Hi $1'});
  });

  test('leaves out disabled extensions', () async {
    amo.publish(
      slug: 's',
      guid: 'sample@test',
      version: '1.0',
      files: extension(),
    );
    await installer.installFromAmo('s');
    await registry.setEnabled('sample@test', enabled: false);

    expect((await state())['extensions'], isEmpty);
  });

  test(
    'an extension that is not installed intact is skipped, not fatal',
    () async {
      amo.publish(
        slug: 's',
        guid: 'sample@test',
        version: '1.0',
        files: extension(),
      );
      final installed = (await installer.installFromAmo('s')).extension;
      File(
        '${registry.directoryFor(installed).path}/manifest.json',
      ).deleteSync();

      expect((await state())['extensions'], isEmpty);
    },
  );

  test('runs a content script only where host access was granted', () async {
    // MV3: content script matches are not granted by themselves; only the
    // host_permissions are.
    amo.publish(
      slug: 's',
      guid: 'sample@test',
      version: '1.0',
      files: extension(
        manifestVersion: 3,
        extraManifest: {
          'host_permissions': ['https://granted.example/*'],
        },
        contentScripts: [
          {
            'matches': ['https://granted.example/*', 'https://other.example/*'],
            'js': ['a.js'],
          },
          {
            'matches': ['https://other.example/*'],
            'js': ['a.js'],
          },
        ],
      ),
    );
    await installer.installFromAmo('s');

    final entry =
        ((await state())['extensions']! as List).single as Map<String, Object?>;
    final scripts = entry['contentScripts']! as List;
    expect(
      scripts,
      hasLength(1),
      reason: 'the script with no granted match is dropped',
    );
    expect((scripts.single as Map)['matches'], ['https://granted.example/*']);
  });

  test('MV2 grants what its content scripts ask for', () async {
    amo.publish(
      slug: 's',
      guid: 'sample@test',
      version: '1.0',
      files: extension(),
    );
    await installer.installFromAmo('s');

    final entry =
        ((await state())['extensions']! as List).single as Map<String, Object?>;
    expect(entry['contentScripts'], hasLength(1));
  });

  test('marks MAIN world scripts', () async {
    amo.publish(
      slug: 's',
      guid: 'sample@test',
      version: '1.0',
      files: extension(
        contentScripts: [
          {
            'matches': ['https://example.com/*'],
            'js': ['a.js'],
            'world': 'MAIN',
          },
        ],
      ),
    );
    await installer.installFromAmo('s');

    final entry =
        ((await state())['extensions']! as List).single as Map<String, Object?>;
    expect(((entry['contentScripts']! as List).single as Map)['world'], 'MAIN');
  });

  test('runs a registered script in the world it was registered for', () async {
    amo.publish(
      slug: 's',
      guid: 'sample@test',
      version: '1.0',
      files: extension(),
    );
    await installer.installFromAmo('s');

    // As uBlock Origin registers its scriptlets.
    final built =
        jsonDecode(
              await EngineStateBuilder(
                registry: registry,
                dynamicScripts: (_) => [
                  const DynamicContentScript('page', {
                    'matches': ['https://video.example/*'],
                    'js': [
                      {'code': 'page()'},
                    ],
                    'runAt': 'document_start',
                    'world': 'MAIN',
                    'matchOriginAsFallback': true,
                  }),
                  const DynamicContentScript('own', {
                    'matches': ['https://video.example/*'],
                    'js': [
                      {'code': 'own()'},
                    ],
                  }),
                ],
              ).build(),
            )
            as Map<String, Object?>;

    final entry = (built['extensions']! as List).single as Map<String, Object?>;
    final scripts = (entry['contentScripts']! as List)
        .cast<Map<String, Object?>>()
        .skip(1);
    expect(scripts.map((script) => script['world']), ['MAIN', 'ISOLATED']);
    expect(scripts.map((script) => script['matchAboutBlank']), [true, false]);
  });

  test('is a valid empty document when nothing is installed', () async {
    final built = await state();
    expect(built['extensions'], isEmpty);
    expect(built['shim'], isNotEmpty);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

import 'support/fake_amo.dart';
import 'support/node_world.dart';

void main() {
  if (!hasNode) {
    test('skipped: node is not available', () {}, skip: 'needs node');
    return;
  }

  late Directory temp;
  late Directory hosts;
  late FakeAmo amo;
  late ExtensionRegistry registry;
  late ExtensionInstaller installer;
  late WorldTransport transport;
  late ExtensionHost host;
  final worlds = <NodeWorld>[];
  var nextContextId = 1;

  const extensionId = 'native@test';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bird_native_');
    hosts = await Directory('${temp.path}/hosts').create();
    amo = FakeAmo();
    registry = await ExtensionRegistry.open(Directory('${temp.path}/ext'));
    installer = ExtensionInstaller(registry: registry, amo: AmoClient(amo));
    transport = WorldTransport();
    host = ExtensionHost(
      registry: registry,
      transport: transport,
      stateBuilder: EngineStateBuilder(registry: registry),
      apis: [
        NativeMessagingApi(locator: NativeHostLocator(directories: [hosts])),
      ],
    );
    nextContextId = 1;
    await host.start();
  });

  tearDown(() async {
    await host.dispose();
    for (final world in worlds) {
      await world.close();
    }
    worlds.clear();
    await registry.dispose();
    await temp.delete(recursive: true);
  });

  /// Installs a native host manifest for the test host program.
  Future<File> installHost({
    String name = 'com.example.echo',
    List<String> allowed = const [extensionId],
    String? path,
  }) async {
    final program = File('test/support/native_host.js').absolute.path;
    final file = File('${hosts.path}/$name.json');
    await file.writeAsString(
      jsonEncode({
        'name': name,
        'description': 'A host for tests',
        'path': path ?? program,
        'type': 'stdio',
        'allowed_extensions': allowed,
      }),
    );
    return file;
  }

  Future<({ExtensionContext context, NodeWorld world})> openPage({
    List<String> permissions = const ['nativeMessaging'],
  }) async {
    amo.publish(
      slug: 'native',
      guid: extensionId,
      version: '1.0',
      files: sampleExtension(id: extensionId, permissions: permissions),
    );
    final extension = (await installer.installFromAmo('native')).extension;

    final context = ExtensionContext(
      contextId: nextContextId++,
      viewId: null,
      extensionUuid: extension.uuid,
      url: '${extension.origin}/background.html',
      isTopLevel: true,
    );
    final world = await NodeWorld.start(
      state:
          jsonDecode(await EngineStateBuilder(registry: registry).build())
              as Map<String, Object?>,
      extensionUuid: extension.uuid,
      isPage: true,
    );
    worlds.add(world);
    await transport.attach(context, world);
    return (context: context, world: world);
  }

  Future<void> eventually(Future<bool> Function() check) async {
    for (var i = 0; i < 150; i++) {
      if (await check()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('did not happen in time');
  }

  Future<Object?> json(NodeWorld world, String code) async =>
      jsonDecode(jsonEncode(await world.run(code)));

  group('connectNative', () {
    test('messages go both ways, and the host is told who is asking', () async {
      final manifest = await installHost();
      final page = await openPage();

      await page.world.run('''
        globalThis.received = [];
        globalThis.port = browser.runtime.connectNative('com.example.echo');
        port.onMessage.addListener((m) => received.push(m));
        port.postMessage({ hello: 'world' });
        port.postMessage([1, 2, 3]);
      ''');

      await eventually(
        () async => (await json(page.world, 'received.length')) == 2,
      );
      final received = await json(page.world, 'received') as List;

      // The host is started with its manifest and the extension's id, and
      // answers in order. The first message was posted before it had started.
      expect(received[0]['echo'], {'hello': 'world'});
      expect(received[0]['args'], [manifest.path, extensionId]);
      expect(received[1]['echo'], [1, 2, 3]);
    });

    test('a host that exits disconnects the port', () async {
      await installHost();
      final page = await openPage();

      await page.world.run('''
        globalThis.disconnected = null;
        globalThis.port = browser.runtime.connectNative('com.example.echo');
        port.onDisconnect.addListener((p) => { disconnected = p.error ? p.error.message : 'clean'; });
        port.postMessage({ cmd: 'exit' });
      ''');

      await eventually(
        () async => (await json(page.world, 'disconnected')) == 'clean',
      );
      expect(
        () => page.world.run('port.postMessage({})'),
        throwsA(anything),
        reason: 'a disconnected port cannot be posted to',
      );
    });

    test('a host that is not installed refuses the connection', () async {
      final page = await openPage();

      await page.world.run('''
        globalThis.error = null;
        globalThis.port = browser.runtime.connectNative('com.example.nothing');
        port.onDisconnect.addListener((p) => { error = p.error && p.error.message; });
      ''');

      await eventually(
        () async => (await json(page.world, 'error')) != null,
      );
      expect(
        await json(page.world, 'error'),
        'No such native application com.example.nothing',
      );
    });

    test('only the extensions a host lists may use it', () async {
      await installHost(allowed: ['someone-else@test']);
      final page = await openPage();

      await page.world.run('''
        globalThis.error = null;
        globalThis.port = browser.runtime.connectNative('com.example.echo');
        port.onDisconnect.addListener((p) => { error = p.error && p.error.message; });
      ''');

      await eventually(
        () async => (await json(page.world, 'error')) != null,
      );
      expect(
        '${await json(page.world, 'error')}',
        contains('does not have permission'),
      );
    });

    test('a name cannot reach outside the host directories', () async {
      await installHost();
      final page = await openPage();

      await page.world.run('''
        globalThis.error = null;
        globalThis.port = browser.runtime.connectNative('../ext/evil');
        port.onDisconnect.addListener((p) => { error = p.error && p.error.message; });
      ''');

      await eventually(
        () async => (await json(page.world, 'error')) != null,
      );
      expect(
        '${await json(page.world, 'error')}',
        contains('No such native application'),
      );
    });

    test('an extension without the permission cannot connect', () async {
      await installHost();
      final page = await openPage(permissions: const ['storage']);

      await page.world.run('''
        globalThis.error = null;
        globalThis.port = browser.runtime.connectNative('com.example.echo');
        port.onDisconnect.addListener((p) => { error = p.error && p.error.message; });
      ''');

      await eventually(
        () async => (await json(page.world, 'error')) != null,
      );
      expect('${await json(page.world, 'error')}', contains('nativeMessaging'));
    });
  });

  group('sendNativeMessage', () {
    test('resolves with the first answer of the host', () async {
      await installHost();
      final page = await openPage();

      final answer =
          await json(
                page.world,
                "browser.runtime.sendNativeMessage('com.example.echo', { ping: 1 })",
              )
              as Map;
      expect(answer['echo'], {'ping': 1});
    });

    test('rejects for a host that is not there', () async {
      final page = await openPage();
      await expectLater(
        page.world.run(
          "browser.runtime.sendNativeMessage('com.example.nothing', {})",
        ),
        throwsA(
          predicate((e) => '$e'.contains('No such native application')),
        ),
      );
    });
  });

  group('content scripts', () {
    test('cannot reach native applications', () async {
      await installHost();
      amo.publish(
        slug: 'native',
        guid: extensionId,
        version: '1.0',
        files: sampleExtension(
          id: extensionId,
          permissions: const ['nativeMessaging'],
        ),
      );
      final extension = (await installer.installFromAmo('native')).extension;
      final context = ExtensionContext(
        contextId: nextContextId++,
        viewId: 1,
        extensionUuid: extension.uuid,
        url: 'https://example.com/page',
        isTopLevel: true,
      );
      final world = await NodeWorld.start(
        state:
            jsonDecode(await EngineStateBuilder(registry: registry).build())
                as Map<String, Object?>,
        extensionUuid: extension.uuid,
      );
      worlds.add(world);
      await transport.attach(context, world);

      expect(await json(world, 'typeof browser.runtime.connectNative'), 'undefined');
    });
  });
}

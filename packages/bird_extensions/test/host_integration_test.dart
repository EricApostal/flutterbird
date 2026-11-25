// The real shim in Node, talking to the real host, through a fake transport:
// everything of an extension call except the engine itself.
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
  late FakeAmo amo;
  late ExtensionRegistry registry;
  late ExtensionInstaller installer;
  late WorldTransport transport;
  late ExtensionHost host;
  final worlds = <NodeWorld>[];
  var nextContextId = 1;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bird_host_');
    amo = FakeAmo();
    registry = await ExtensionRegistry.open(Directory('${temp.path}/ext'));
    installer = ExtensionInstaller(registry: registry, amo: AmoClient(amo));
    transport = WorldTransport();
    host = ExtensionHost(
      registry: registry,
      transport: transport,
      stateBuilder: EngineStateBuilder(registry: registry),
      apis: [StorageApi(Directory('${temp.path}/ext/storage'))],
    );
    nextContextId = 1;
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

  Future<InstalledExtension> install({
    String slug = 'sample',
    String id = 'sample@test',
    List<String> permissions = const ['storage'],
  }) async {
    amo.publish(
      slug: slug,
      guid: id,
      version: '1.0',
      files: sampleExtension(id: id, permissions: permissions),
    );
    return (await installer.installFromAmo(slug)).extension;
  }

  Future<Map<String, Object?>> currentState() async =>
      jsonDecode(await EngineStateBuilder(registry: registry).build())
          as Map<String, Object?>;

  /// A world for [extension]: a content script on a page, or one of its own pages.
  Future<({ExtensionContext context, NodeWorld world})> openContext(
    InstalledExtension extension, {
    String? url,
    int? viewId = 7,
    bool isTopLevel = true,
  }) async {
    final context = ExtensionContext(
      contextId: nextContextId++,
      viewId: viewId,
      extensionUuid: extension.uuid,
      url: url ?? 'https://example.com/page',
      isTopLevel: isTopLevel,
    );
    final world = await NodeWorld.start(
      state: await currentState(),
      extensionUuid: extension.uuid,
    );
    worlds.add(world);
    await transport.attach(context, world);
    return (context: context, world: world);
  }

  group('content size', () {
    test('a page tells how much room its content takes', () async {
      await host.start();
      final extension = await install();
      final page = await openContext(
        extension,
        url: '${extension.origin}/popup.html',
      );

      final sizes = <ExtensionContentSize>[];
      final subscription = host.contentSizes.listen(sizes.add);

      transport.inject(
        page.context.contextId,
        jsonEncode({
          'id': 1,
          'ns': 'bird',
          'method': 'contentSize',
          'args': [340, 412],
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(sizes, hasLength(1));
      expect(sizes.single.context.contextId, page.context.contextId);
      expect(sizes.single.width, 340);
      expect(sizes.single.height, 412);
    });
  });

  group('state', () {
    test(
      'is given to the processes at start and when extensions change',
      () async {
        await host.start();
        expect(transport.states, hasLength(1));
        expect(
          (jsonDecode(transport.states.last) as Map)['extensions'],
          isEmpty,
        );

        await install();
        await host.pushState();
        expect(
          ((jsonDecode(transport.states.last) as Map)['extensions'] as List),
          hasLength(1),
        );

        await installer.uninstall('sample@test');
        await host.pushState();
        expect(
          (jsonDecode(transport.states.last) as Map)['extensions'],
          isEmpty,
        );
      },
    );
  });

  group('storage', () {
    test('round trips values and persists them', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      final stored = await cs.world.run('''
        browser.storage.local
          .set({a: 1, b: {c: [2, 3]}})
          .then(() => browser.storage.local.get(['a', 'b', 'missing']))
      ''');
      expect(stored, {
        'a': 1,
        'b': {
          'c': [2, 3],
        },
      });

      final file = File(
        '${temp.path}/ext/storage/${extension.uuid}/local.json',
      );
      expect(jsonDecode(file.readAsStringSync()), {
        'a': 1,
        'b': {
          'c': [2, 3],
        },
      });
    });

    test('get supports no keys, a string, and defaults', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      await cs.world.run('browser.storage.local.set({x: 1, y: 2})');
      expect(await cs.world.run('browser.storage.local.get()'), {
        'x': 1,
        'y': 2,
      });
      expect(await cs.world.run('browser.storage.local.get("x")'), {'x': 1});
      expect(await cs.world.run('browser.storage.local.get({x: 9, z: 5})'), {
        'x': 1,
        'z': 5,
      });
    });

    test('remove and clear', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      await cs.world.run('browser.storage.local.set({x: 1, y: 2, z: 3})');
      await cs.world.run('browser.storage.local.remove(["x", "nope"])');
      expect(await cs.world.run('browser.storage.local.get()'), {
        'y': 2,
        'z': 3,
      });
      await cs.world.run('browser.storage.local.clear()');
      expect(await cs.world.run('browser.storage.local.get()'), isEmpty);
    });

    test('areas are separate, and session is not persisted', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      await cs.world.run('browser.storage.local.set({k: "local"})');
      await cs.world.run('browser.storage.session.set({k: "session"})');
      expect(await cs.world.run('browser.storage.local.get("k")'), {
        'k': 'local',
      });
      expect(await cs.world.run('browser.storage.session.get("k")'), {
        'k': 'session',
      });

      final dir = Directory('${temp.path}/ext/storage/${extension.uuid}');
      expect(File('${dir.path}/local.json').existsSync(), isTrue);
      expect(File('${dir.path}/session.json').existsSync(), isFalse);
    });

    test('managed storage reads as empty and cannot be written', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      expect(await cs.world.run('browser.storage.managed.get()'), isEmpty);
      expect(await cs.world.run('browser.storage.managed.get({d: 1})'), {
        'd': 1,
      });
      await expectLater(
        cs.world.run('browser.storage.managed.set({a: 1})'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('read-only'),
          ),
        ),
      );
    });

    test('values read back are copies', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      await cs.world.run('browser.storage.local.set({o: {n: 1}})');
      await cs.world.run(
        'browser.storage.local.get("o").then((r) => { r.o.n = 99; })',
      );
      expect(await cs.world.run('browser.storage.local.get("o")'), {
        'o': {'n': 1},
      });
    });

    test('changes reach every context of the extension', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      final page = await openContext(
        extension,
        url: '${extension.origin}/background.html',
        viewId: null,
      );

      await page.world.run('''
        globalThis.changes = [];
        browser.storage.onChanged.addListener((c, area) => changes.push([c, area]));
      ''');

      await cs.world.run('browser.storage.local.set({a: 1})');
      await cs.world.run('browser.storage.local.set({a: 2})');
      await cs.world.run('browser.storage.local.set({a: 2})');
      await cs.world.run('browser.storage.local.remove("a")');

      Object? seen;
      for (var i = 0; i < 50; i++) {
        seen = await page.world.run('changes.length');
        if (seen == 3) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await page.world.run('changes'), [
        [
          {
            'a': {'newValue': 1},
          },
          'local',
        ],
        [
          {
            'a': {'oldValue': 1, 'newValue': 2},
          },
          'local',
        ],
        [
          {
            'a': {'oldValue': 2},
          },
          'local',
        ],
      ], reason: 'setting the same value again is not a change');
    });

    test('is refused without the storage permission', () async {
      final extension = await install(permissions: const []);
      await host.start();
      final cs = await openContext(extension);

      await expectLater(
        cs.world.run('browser.storage.local.get()'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('"storage" permission'),
          ),
        ),
      );
    });

    test('is removed with the extension', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      await cs.world.run('browser.storage.local.set({a: 1})');

      final dir = Directory('${temp.path}/ext/storage/${extension.uuid}');
      expect(dir.existsSync(), isTrue);

      await installer.uninstall('sample@test');
      for (var i = 0; i < 50 && dir.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(dir.existsSync(), isFalse);
    });
  });

  group('messaging', () {
    test('a content script gets an answer from the extension page', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension, viewId: 7);
      final page = await openContext(
        extension,
        url: '${extension.origin}/background.html',
        viewId: null,
      );

      await page.world.run('''
        globalThis.senders = [];
        browser.runtime.onMessage.addListener((message, sender) => {
          senders.push(sender);
          return Promise.resolve({echo: message});
        });
      ''');

      expect(await cs.world.run('browser.runtime.sendMessage({n: 1})'), {
        'echo': {'n': 1},
      });

      final sender = (await page.world.run('senders') as List).single as Map;
      expect(sender['id'], 'sample@test');
      expect(sender['url'], 'https://example.com/page');
      expect(sender['tab'], {'id': 7, 'url': 'https://example.com/page'});
      expect(sender['frameId'], 0);
    });

    test('sendResponse works as well as a returned promise', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      final page = await openContext(
        extension,
        url: '${extension.origin}/background.html',
        viewId: null,
      );

      await page.world.run('''
        browser.runtime.onMessage.addListener((m, s, sendResponse) => {
          setTimeout(() => sendResponse("late " + m), 5);
          return true;
        });
      ''');
      expect(await cs.world.run('browser.runtime.sendMessage("x")'), 'late x');
    });

    test('is refused when nothing is listening anywhere', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      await expectLater(
        cs.world.run('browser.runtime.sendMessage("x")'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Receiving end does not exist'),
          ),
        ),
      );
    });

    test('resolves with nothing when the page has no answer', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      final page = await openContext(
        extension,
        url: '${extension.origin}/background.html',
        viewId: null,
      );

      await page.world.run('browser.runtime.onMessage.addListener(() => {})');
      expect(await cs.world.run('browser.runtime.sendMessage("x")'), isNull);
    });

    test('rejects when the listener fails', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      final page = await openContext(
        extension,
        url: '${extension.origin}/background.html',
        viewId: null,
      );

      await page.world.run(
        'browser.runtime.onMessage.addListener(async () => { throw new Error("listener broke"); })',
      );
      await expectLater(
        cs.world.run('browser.runtime.sendMessage("x")'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('listener broke'),
          ),
        ),
      );
    });

    test(
      'resolves with nothing if the page goes away without answering',
      () async {
        final extension = await install();
        await host.start();
        final cs = await openContext(extension);
        final page = await openContext(
          extension,
          url: '${extension.origin}/background.html',
          viewId: null,
        );

        await page.world.run(
          'browser.runtime.onMessage.addListener(() => true)',
        );
        final answer = cs.world.run('browser.runtime.sendMessage("x")');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await transport.destroy(page.context.contextId);

        expect(await answer, isNull);
      },
    );

    test('only a context the message was delivered to can answer it', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      final page = await openContext(
        extension,
        url: '${extension.origin}/background.html',
        viewId: null,
      );
      final bystander = await openContext(extension, viewId: 8);

      await page.world.run('''
        browser.runtime.onMessage.addListener((m, s, sendResponse) => {
          setTimeout(() => sendResponse("real"), 100);
          return true;
        });
      ''');

      final answer = cs.world.run('browser.runtime.sendMessage("x")');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // The first message sent gets token 1. A context that was not asked
      // tries to answer it.
      transport.inject(
        bystander.context.contextId,
        jsonEncode({
          'id': 9,
          'ns': 'bird',
          'method': 'respond',
          'args': [
            1,
            {'handled': true, 'value': 'forged'},
          ],
        }),
      );

      expect(await answer, 'real');
    });

    test('does not reach other extensions', () async {
      final first = await install();
      final second = await install(slug: 'other', id: 'other@test');
      await host.start();
      final cs = await openContext(first);
      final otherPage = await openContext(
        second,
        url: '${second.origin}/background.html',
        viewId: null,
      );
      await otherPage.world.run(
        'browser.runtime.onMessage.addListener(() => "heard")',
      );

      await expectLater(
        cs.world.run('browser.runtime.sendMessage("x")'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('calls', () {
    // Raw traffic, as a shim (or something pretending to be one) would send it.
    Map<String, Object?> lastReply(int contextId) =>
        jsonDecode(transport.delivered[contextId]!.last)
            as Map<String, Object?>;

    test('an API the host does not have answers with an error', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      transport.inject(
        cs.context.contextId,
        jsonEncode({'id': 41, 'ns': 'tabs', 'method': 'query', 'args': []}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(lastReply(cs.context.contextId), {
        'reply': 41,
        'error': {'message': 'tabs.query is not supported'},
      });
    });

    test(
      'a method the host does not have in a namespace it does answers too',
      () async {
        final extension = await install();
        await host.start();
        final cs = await openContext(extension);

        transport.inject(
          cs.context.contextId,
          jsonEncode({
            'id': 1,
            'ns': 'storage',
            'method': 'explode',
            'args': ['local'],
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          (lastReply(cs.context.contextId)['error'] as Map)['message'],
          contains('not supported'),
        );
      },
    );

    test('an unknown storage area is an error, not a crash', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);

      transport.inject(
        cs.context.contextId,
        jsonEncode({
          'id': 2,
          'ns': 'storage',
          'method': 'get',
          'args': ['bogus'],
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        (lastReply(cs.context.contextId)['error'] as Map)['message'],
        contains('Unknown storage area'),
      );
    });

    test('traffic that is not a well-formed call is ignored', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      final before = transport.delivered[cs.context.contextId]?.length ?? 0;

      for (final payload in [
        'not json',
        '[]',
        '42',
        jsonEncode({'ns': 'storage', 'method': 'get'}),
        jsonEncode({'id': 'one', 'ns': 'storage', 'method': 'get'}),
        jsonEncode({'id': 1, 'ns': 5, 'method': 'get'}),
      ]) {
        transport.inject(cs.context.contextId, payload);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(transport.delivered[cs.context.contextId]?.length ?? 0, before);
    });

    test(
      'traffic from a context the host was never told about is ignored',
      () async {
        final extension = await install();
        await host.start();
        await openContext(extension);

        transport.inject(
          999,
          jsonEncode({
            'id': 1,
            'ns': 'storage',
            'method': 'get',
            'args': ['local'],
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(transport.delivered[999], isNull);
      },
    );

    test(
      'a forged answer for a message that was not sent is harmless',
      () async {
        final extension = await install();
        await host.start();
        final cs = await openContext(extension);

        transport.inject(
          cs.context.contextId,
          jsonEncode({
            'id': 3,
            'ns': 'bird',
            'method': 'respond',
            'args': [
              12345,
              {'handled': true, 'value': 'x'},
            ],
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(lastReply(cs.context.contextId)['reply'], 3);
      },
    );

    test('a call from a context that is gone is dropped', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      await transport.destroy(cs.context.contextId);

      // Nothing to assert beyond not crashing: the world is no longer wired up.
      expect(host.contexts, isEmpty);
    });

    test('a disabled extension cannot call in', () async {
      final extension = await install();
      await host.start();
      final cs = await openContext(extension);
      await registry.setEnabled('sample@test', enabled: false);

      await expectLater(
        cs.world.run('browser.storage.local.get()'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not available'),
          ),
        ),
      );
    });
  });
}

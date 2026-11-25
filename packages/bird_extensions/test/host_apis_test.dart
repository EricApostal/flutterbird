// The browser-facing APIs, each exercised through the real shim in Node.
import 'dart:convert';
import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

import 'support/fake_amo.dart';
import 'support/fake_browser.dart';
import 'support/node_world.dart';

const _all = [
  'storage',
  'tabs',
  'webNavigation',
  'webRequest',
  'webRequestBlocking',
  'alarms',
  'dns',
  'menus',
  'idle',
  'notifications',
  'scripting',
  'downloads',
  '<all_urls>',
];

void main() {
  if (!hasNode) {
    test('skipped: node is not available', () {}, skip: 'needs node');
    return;
  }

  late Directory temp;
  late FakeAmo amo;
  late FakeBrowser browser;
  late ExtensionRegistry registry;
  late ExtensionInstaller installer;
  late WorldTransport transport;
  late ExtensionHost host;
  late ActionStore actions;
  late MenusApi menus;
  late WebRequestApi webRequest;
  late ContentScriptsApi contentScripts;
  final worlds = <NodeWorld>[];
  var nextContextId = 1;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bird_apis_');
    amo = FakeAmo();
    browser = FakeBrowser();
    registry = await ExtensionRegistry.open(Directory('${temp.path}/ext'));
    installer = ExtensionInstaller(registry: registry, amo: AmoClient(amo));
    transport = WorldTransport();
    actions = ActionStore();
    menus = MenusApi();
    webRequest = WebRequestApi();
    contentScripts = ContentScriptsApi();
    host = ExtensionHost(
      registry: registry,
      transport: transport,
      browser: browser,
      stateBuilder: EngineStateBuilder(
        registry: registry,
        dynamicScripts: contentScripts.scriptsFor,
      ),
      apis: [
        StorageApi(Directory('${temp.path}/ext/storage')),
        TabsApi(),
        WindowsApi(),
        WebNavigationApi(),
        ActionApi('browserAction', actions),
        ActionApi('action', actions),
        menus,
        AlarmsApi(),
        CommandsApi(),
        PermissionsApi(),
        DnsApi(),
        IdleApi(),
        NotificationsApi(),
        ManagementApi(),
        DownloadsApi(),
        ScriptingApi(),
        contentScripts,
        webRequest,
      ],
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
    List<String> permissions = _all,
  }) async {
    amo.publish(
      slug: slug,
      guid: id,
      version: '1.0',
      files: sampleExtension(id: id, permissions: permissions),
    );
    return (await installer.installFromAmo(slug)).extension;
  }

  Future<({ExtensionContext context, NodeWorld world})> open(
    InstalledExtension extension, {
    String? url,
    int? viewId,
    bool isTopLevel = true,
    bool isPage = false,
  }) async {
    final context = ExtensionContext(
      contextId: nextContextId++,
      viewId: viewId,
      extensionUuid: extension.uuid,
      url:
          url ??
          (isPage
              ? '${extension.origin}/background.html'
              : 'https://example.com/page'),
      isTopLevel: isTopLevel,
    );
    final world = await NodeWorld.start(
      state:
          jsonDecode(await EngineStateBuilder(registry: registry).build())
              as Map<String, Object?>,
      extensionUuid: extension.uuid,
      isPage: isPage || url?.startsWith('moz-extension:') == true,
    );
    worlds.add(world);
    await transport.attach(context, world);
    return (context: context, world: world);
  }

  /// Waits until [check] holds, polling the world for what an event left.
  Future<void> eventually(Future<bool> Function() check) async {
    for (var i = 0; i < 100; i++) {
      if (await check()) return;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('the condition never became true');
  }

  group('background pages', () {
    test(
      'start for enabled extensions with a background and stop with them',
      () async {
        final extension = await install();
        await host.start();

        expect(browser.startedPages, [
          '${extension.origin}/_generated_background_page.html',
        ]);

        await registry.setEnabled('sample@test', enabled: false);
        await eventually(() async => browser.stoppedPages.isNotEmpty);
        expect(browser.stoppedPages, [extension.uuid]);

        await registry.setEnabled('sample@test', enabled: true);
        await eventually(() async => browser.startedPages.length == 2);
      },
    );

    test('a generated page loads the manifest\'s scripts', () async {
      final extension = await install();
      final page = File(
        '${registry.directoryFor(extension).path}/_generated_background_page.html',
      ).readAsStringSync();
      expect(page, contains('<script src="background.js"></script>'));
    });

    test('restart on update and stop on removal', () async {
      final extension = await install();
      await host.start();
      amo.publish(
        slug: 'sample',
        guid: 'sample@test',
        version: '1.1',
        files: sampleExtension(version: '1.1', permissions: _all),
      );
      await installer.update('sample@test');
      await eventually(() async => browser.startedPages.length == 2);
      expect(browser.stoppedPages, contains(extension.uuid));

      await installer.uninstall('sample@test');
      await eventually(() async => browser.stoppedPages.length >= 2);
    });

    test('reload restarts the background page', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      await page.world.run('browser.runtime.reload()');
      await eventually(() async => browser.startedPages.length == 2);
    });
  });

  group('ports', () {
    test('a content script and the background page talk both ways', () async {
      final extension = await install();
      await host.start();
      final background = await open(extension, isPage: true);
      final cs = await open(extension, viewId: 7);

      await background.world.run('''
        globalThis.received = [];
        browser.runtime.onConnect.addListener((port) => {
          received.push(['connect', port.name, port.sender.tab && port.sender.tab.id]);
          port.onMessage.addListener((m) => { received.push(['msg', m]); port.postMessage({echo: m}); });
          port.onDisconnect.addListener(() => received.push(['bye']));
        });
      ''');

      await cs.world.run('''
        globalThis.back = [];
        globalThis.port = browser.runtime.connect({name: 'vapi'});
        port.onMessage.addListener((m) => back.push(m));
        port.postMessage({hello: 1});
        0
      ''');

      await eventually(
        () async => ((await cs.world.run('back.length')) as int) == 1,
      );
      expect(await cs.world.run('back'), [
        {
          'echo': {'hello': 1},
        },
      ]);
      expect(await background.world.run('received'), [
        ['connect', 'vapi', 7],
        [
          'msg',
          {'hello': 1},
        ],
      ]);

      await cs.world.run('port.disconnect()');
      await eventually(
        () async =>
            ((await background.world.run('received.length')) as int) == 3,
      );
      expect((await background.world.run('received') as List).last, ['bye']);
    });

    test('the background page can end a port', () async {
      final extension = await install();
      await host.start();
      final background = await open(extension, isPage: true);
      final cs = await open(extension, viewId: 7);

      await background.world.run(
        'browser.runtime.onConnect.addListener((p) => p.disconnect())',
      );
      await cs.world.run(
        'globalThis.gone = 0; globalThis.port = browser.runtime.connect({name: "x"}); port.onDisconnect.addListener(() => gone++); 0',
      );
      await eventually(() async => (await cs.world.run('gone')) == 1);
    });

    test('connecting with nobody listening fails the port', () async {
      final extension = await install();
      await host.start();
      final cs = await open(extension, viewId: 7);

      await cs.world.run(
        'globalThis.why = null; globalThis.port = browser.runtime.connect({name: "x"}); port.onDisconnect.addListener((p) => { why = p.error && p.error.message; }); 0',
      );
      await eventually(() async => (await cs.world.run('why')) != null);
      expect(
        await cs.world.run('why'),
        contains('Receiving end does not exist'),
      );
    });

    test('a port closes when the context at the other end goes away', () async {
      final extension = await install();
      await host.start();
      final background = await open(extension, isPage: true);
      final cs = await open(extension, viewId: 7);

      await background.world.run(
        'browser.runtime.onConnect.addListener((p) => {})',
      );
      await cs.world.run(
        'globalThis.gone = 0; globalThis.port = browser.runtime.connect({name: "x"}); port.onDisconnect.addListener(() => gone++); 0',
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await transport.destroy(background.context.contextId);
      await eventually(() async => (await cs.world.run('gone')) == 1);
    });

    test('the background page reaches a tab with tabs.connect', () async {
      final extension = await install();
      await host.start();
      final tab = browser.open('https://example.com/page', id: 7);
      final background = await open(extension, isPage: true);
      final cs = await open(extension, viewId: tab.id);

      await cs.world.run('''
        globalThis.got = [];
        browser.runtime.onConnect.addListener((p) => { p.onMessage.addListener((m) => got.push(m)); });
        0
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await background.world.run(
        'globalThis.p = browser.tabs.connect(7, {name: "bg"}); p.postMessage("hi"); 0',
      );
      await eventually(
        () async => ((await cs.world.run('got.length')) as int) == 1,
      );
      expect(await cs.world.run('got'), ['hi']);
    });
  });

  group('tabs', () {
    test('query, get and the active tab', () async {
      final extension = await install();
      await host.start();
      browser.open('https://a.example/', id: 1, title: 'A');
      browser.open('https://b.example/', id: 2, title: 'B');
      final page = await open(extension, isPage: true);

      expect(
        await page.world.run(
          'browser.tabs.query({}).then((t) => t.map((x) => x.id))',
        ),
        [1, 2],
      );
      expect(
        await page.world.run(
          'browser.tabs.query({active: true}).then((t) => t.map((x) => x.id))',
        ),
        [2],
      );
      expect(
        await page.world.run(
          'browser.tabs.query({url: "https://a.example/*"}).then((t) => t.map((x) => x.title))',
        ),
        ['A'],
      );
      expect(
        await page.world.run('browser.tabs.get(1).then((t) => t.url)'),
        'https://a.example/',
      );
      await expectLater(
        page.world.run('browser.tabs.get(99)'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'm',
            contains('Invalid tab ID'),
          ),
        ),
      );
    });

    test('create, update and remove', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      final created =
          await page.world.run(
                'browser.tabs.create({url: "https://new.example/"})',
              )
              as Map;
      expect(created['url'], 'https://new.example/');
      expect(browser.tabs.single.url, 'https://new.example/');

      await page.world.run(
        'browser.tabs.update(${created['id']}, {url: "https://moved.example/"})',
      );
      expect(browser.tab(created['id'] as int)!.url, 'https://moved.example/');

      await page.world.run('browser.tabs.remove(${created['id']})');
      expect(browser.tabs, isEmpty);
    });

    test('update with no tab id targets the active tab', () async {
      final extension = await install();
      await host.start();
      browser.open('https://a.example/', id: 1);
      final page = await open(extension, isPage: true);

      await page.world.run('browser.tabs.update({url: "https://z.example/"})');
      expect(browser.tab(1)!.url, 'https://z.example/');
    });

    test('hide where a tab is from an extension that may not see it', () async {
      final blind = await install(permissions: const ['storage']);
      await host.start();
      browser.open('https://secret.example/', id: 1, title: 'Secret');
      final page = await open(blind, isPage: true);

      final tab = await page.world.run('browser.tabs.get(1)') as Map;
      expect(tab.containsKey('url'), isFalse);
      expect(tab.containsKey('title'), isFalse);
      expect(tab['id'], 1);
    });

    test('events: created, updated, activated and removed', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await page.world.run('''
        globalThis.log = [];
        browser.tabs.onCreated.addListener((t) => log.push(['created', t.id]));
        browser.tabs.onUpdated.addListener((id, change, tab) => log.push(['updated', id, change]));
        browser.tabs.onActivated.addListener((i) => log.push(['activated', i.tabId, i.previousTabId]));
        browser.tabs.onRemoved.addListener((id) => log.push(['removed', id]));
        0
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      browser.open('https://a.example/', id: 1);
      browser.open('https://b.example/', id: 2);
      browser.navigate(2, 'https://c.example/', title: 'C');
      await browser.closeTab(2);

      await eventually(
        () async => ((await page.world.run('log.length')) as int) >= 6,
      );
      expect(await page.world.run('log'), [
        ['created', 1],
        ['activated', 1, null],
        ['created', 2],
        ['activated', 2, 1],
        [
          'updated',
          2,
          {'url': 'https://c.example/', 'title': 'C'},
        ],
        ['removed', 2],
      ]);
    });

    test('sendMessage reaches the content script in that tab', () async {
      final extension = await install();
      await host.start();
      final tab = browser.open('https://example.com/page', id: 5);
      final page = await open(extension, isPage: true);
      final cs = await open(extension, viewId: tab.id);
      final other = await open(extension, viewId: 6);

      await cs.world.run(
        'browser.runtime.onMessage.addListener((m) => Promise.resolve("cs got " + m)); 0',
      );
      await other.world.run(
        'browser.runtime.onMessage.addListener(() => Promise.resolve("wrong tab")); 0',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        await page.world.run('browser.tabs.sendMessage(5, "hello")'),
        'cs got hello',
      );
      await expectLater(
        page.world.run('browser.tabs.sendMessage(99, "x")'),
        throwsA(isA<StateError>()),
      );
    });

    test('executeScript runs code in the tab and returns the result', () async {
      final extension = await install();
      await host.start();
      final tab = browser.open('https://example.com/page', id: 5);
      final page = await open(extension, isPage: true);
      await open(extension, viewId: tab.id);

      expect(
        await page.world.run('browser.tabs.executeScript(5, {code: "6 * 7"})'),
        [42],
      );
      expect(
        await page.world.run(
          'browser.tabs.executeScript({code: "\'active\'"})',
        ),
        ['active'],
      );
      expect(
        await page.world.run(
          'browser.tabs.executeScript(5, {file: "background.js"}).then((r) => r.length)',
        ),
        1,
      );
      expect(
        await page.world.run(
          'browser.tabs.executeScript(77, {code: "1"}).catch(() => "no tab")',
        ),
        'no tab',
      );
    });

    test('executeScript can target every frame', () async {
      final extension = await install();
      await host.start();
      final tab = browser.open('https://example.com/page', id: 5);
      final page = await open(extension, isPage: true);
      await open(extension, viewId: tab.id);
      await open(
        extension,
        viewId: tab.id,
        isTopLevel: false,
        url: 'https://frame.example/',
      );

      expect(
        await page.world.run('browser.tabs.executeScript(5, {code: "1"})'),
        [1],
        reason: 'top frame only',
      );
      expect(
        await page.world.run(
          'browser.tabs.executeScript(5, {code: "1", allFrames: true})',
        ),
        [1, 1],
      );
    });

    test('insertCSS is applied in the tab', () async {
      final extension = await install();
      await host.start();
      final tab = browser.open('https://example.com/page', id: 5);
      final page = await open(extension, isPage: true);
      final cs = await open(extension, viewId: tab.id);
      await cs.world.run(
        'globalThis.__bird_insert_css = (css) => { globalThis.inserted = css; }; 0',
      );

      await page.world.run(
        'browser.tabs.insertCSS(5, {code: "a { color: red }"})',
      );
      await eventually(
        () async =>
            (await cs.world.run('globalThis.inserted')) == 'a { color: red }',
      );
    });
  });

  group('windows', () {
    test('describe the one window', () async {
      final extension = await install();
      await host.start();
      browser.open('https://a.example/', id: 1);
      final page = await open(extension, isPage: true);

      final window =
          await page.world.run('browser.windows.getCurrent({populate: true})')
              as Map;
      expect(window['id'], 1);
      expect(window['focused'], isTrue);
      expect((window['tabs'] as List).single['id'], 1);
      expect(
        await page.world.run('browser.windows.getAll().then((w) => w.length)'),
        1,
      );
    });
  });

  group('several windows', () {
    Future<List<Object?>> ids(dynamic page, String query) async =>
        (await page.world.run(
              'browser.tabs.query($query).then((t) => t.map((x) => x.id))',
            ))
            as List<Object?>;

    test('the current window is the one focused last', () async {
      final extension = await install();
      await host.start();
      browser.open('https://a.example/', id: 1);
      browser.open('https://b.example/', id: 2, windowId: 7);
      final page = await open(extension, isPage: true);

      expect(await ids(page, '{active: true}'), [1, 2]);
      expect(await ids(page, '{active: true, currentWindow: true}'), [1]);

      browser.focus(7);
      expect(await ids(page, '{active: true, currentWindow: true}'), [2]);
      expect(await ids(page, '{active: true, lastFocusedWindow: true}'), [2]);
      expect(await ids(page, '{currentWindow: false}'), [1]);
      expect(await ids(page, '{windowId: -2}'), [2]);
      expect(await ids(page, '{windowId: 1}'), [1]);
    });

    test('a document in a tab is in that tab\'s window', () async {
      final extension = await install();
      await host.start();
      browser.open('https://a.example/', id: 1);
      browser.open('https://b.example/', id: 2, windowId: 7);
      final page = await open(extension, isPage: true, viewId: 2);

      expect(await ids(page, '{active: true, currentWindow: true}'), [2]);
      final window =
          await page.world.run('browser.windows.getCurrent()') as Map;
      expect(window['id'], 7);
    });

    test('a popup window can be opened and closed', () async {
      final extension = await install();
      await host.start();
      browser.open('https://a.example/', id: 1);
      final page = await open(extension, isPage: true);

      final made =
          await page.world.run(
                'browser.windows.create('
                '{url: "https://c.example/", type: "popup", width: 400})',
              )
              as Map;
      expect(made['type'], 'popup');
      expect((made['tabs'] as List).single['url'], 'https://c.example/');
      expect(await ids(page, '{windowType: "popup"}'), [
        (made['tabs'] as List).single['id'],
      ]);

      await page.world.run('browser.windows.remove(${made['id']})');
      expect(
        await page.world.run('browser.windows.getAll().then((w) => w.length)'),
        1,
      );
    });

    test('a window that is not there is an error', () async {
      final extension = await install();
      await host.start();
      browser.open('https://a.example/', id: 1);
      final page = await open(extension, isPage: true);

      expect(
        await page.world.run(
          'browser.windows.get(99).then(() => "found", (e) => e.message)',
        ),
        contains('Invalid window ID'),
      );
    });
  });

  group('webNavigation', () {
    test('reports documents of content scripts as navigations', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await page.world.run('''
        globalThis.nav = [];
        for (const name of ['onBeforeNavigate', 'onCommitted', 'onDOMContentLoaded', 'onCompleted']) {
          browser.webNavigation[name].addListener((d) => nav.push([name, d.tabId, d.frameId, d.parentFrameId, d.url]));
        }
        0
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final cs = await open(extension, viewId: 5);
      await eventually(
        () async => ((await page.world.run('nav.length')) as int) >= 2,
      );
      expect(await page.world.run('nav'), [
        ['onBeforeNavigate', 5, 0, -1, 'https://example.com/page'],
        ['onCommitted', 5, 0, -1, 'https://example.com/page'],
      ]);

      transport.inject(
        cs.context.contextId,
        jsonEncode({
          'id': 900,
          'ns': 'bird',
          'method': 'documentEvent',
          'args': ['DOMContentLoaded'],
        }),
      );
      transport.inject(
        cs.context.contextId,
        jsonEncode({
          'id': 901,
          'ns': 'bird',
          'method': 'documentEvent',
          'args': ['load'],
        }),
      );
      await eventually(
        () async => ((await page.world.run('nav.length')) as int) == 4,
      );
      expect(
        ((await page.world.run('nav')) as List)
            .skip(2)
            .map((e) => (e as List).first),
        ['onDOMContentLoaded', 'onCompleted'],
      );
    });

    test('subframes have their own ids and a parent', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await open(extension, viewId: 5);
      final frame = await open(
        extension,
        viewId: 5,
        isTopLevel: false,
        url: 'https://frame.example/x',
      );

      final frames =
          await page.world.run('browser.webNavigation.getAllFrames({tabId: 5})')
              as List;
      expect(frames, hasLength(2));
      final sub = frames.cast<Map<String, Object?>>().firstWhere(
        (f) => f['frameId'] != 0,
      );
      expect(sub['frameId'], frame.context.contextId);
      expect(sub['parentFrameId'], 0);
      expect(sub['url'], 'https://frame.example/x');

      await transport.destroy(frame.context.contextId);
      expect(
        await page.world.run(
          'browser.webNavigation.getAllFrames({tabId: 5}).then((f) => f.length)',
        ),
        1,
      );
    });
  });

  group('APIs an extension touches as it starts', () {
    test('are all there to add listeners to', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      // A missing one of these throws and stops a background page partway
      // through starting, which leaves it deaf to its own content scripts.
      expect(
        await page.world.run('''
          chrome.notifications.onClicked.addListener(() => {});
          chrome.notifications.onButtonClicked.addListener(() => {});
          chrome.notifications.onClosed.addListener(() => {});
          browser.idle.onStateChanged.addListener(() => {});
          browser.idle.setDetectionInterval(60);
          browser.management.onEnabled.addListener(() => {});
          browser.downloads.onChanged.addListener(() => {});
          browser.runtime.onSuspend.addListener(() => {});
          typeof browser.scripting.executeScript
        '''),
        'function',
      );
    });

    test('answer', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      final answers = jsonDecode(
        jsonEncode(
          await page.world.run('''
            Promise.all([
              browser.idle.queryState(60),
              chrome.notifications.create('saved', {type: 'basic', title: 't', message: 'm'}),
              browser.notifications.clear('saved'),
              browser.management.getSelf().then((self) => self.id),
              browser.browserAction.getUserSettings().then((s) => s.isOnToolbar),
            ])
          '''),
        ),
      );
      expect(answers, ['active', 'saved', true, extension.id, true]);
    });

    test('privacy settings answer a callback and remember a change', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      // The chrome form, with a callback, as a password manager calls it.
      final values = jsonDecode(
        jsonEncode(
          await page.world.run('''
            (async () => {
              const read = () => new Promise((done) =>
                chrome.privacy.services.passwordSavingEnabled.get({}, (s) => done(s)));
              const before = await read();
              await browser.privacy.services.passwordSavingEnabled.set({value: true});
              const after = await read();
              await browser.privacy.services.autofillEnabled.get({});
              await browser.privacy.services.autofillAddressEnabled.get({});
              await browser.privacy.services.autofillCreditCardEnabled.get({});
              return [before.value, before.levelOfControl, after.value, after.levelOfControl];
            })()
          '''),
        ),
      );
      expect(values, [
        false,
        'controllable_by_this_extension',
        true,
        'controlled_by_this_extension',
      ]);
    });

    test('scripting runs a function in a tab and names the frame', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await open(extension, viewId: 1);

      final results = jsonDecode(
        jsonEncode(
          await page.world.run('''
            browser.scripting.executeScript({
              target: {tabId: 1},
              func: (a, b) => a + b,
              args: [2, 3],
            })
          '''),
        ),
      );
      expect(results, [
        {'frameId': 0, 'result': 5},
      ]);
    });
  });

  group('browserAction', () {
    test(
      'shows the extension\'s own icon when the button names none',
      () async {
        final extension = await install();
        await host.start();

        // The sample extension has icons and no browser_action.
        final manifest = (await host.manifestOf(extension))!;
        actions.setDefaults(extension, manifest);
        expect(actions.stateFor(extension.uuid).iconPath, 'icon.png');
      },
    );

    test('openPopup asks the app to open the popup', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      final requests = <String>[];
      final subscription = actions.popupRequests.listen(requests.add);
      await page.world.run('browser.browserAction.openPopup()');
      await eventually(() async => requests.isNotEmpty);
      await subscription.cancel();

      expect(requests, [extension.uuid]);
    });

    test('keeps what the extension sets, per tab and overall', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      await page.world.run('''
        browser.browserAction.setBadgeText({text: "12"});
        browser.browserAction.setBadgeText({text: "3", tabId: 7});
        browser.browserAction.setBadgeBackgroundColor({color: "#ff0000"});
        browser.browserAction.setTitle({title: "Blocked"});
        browser.browserAction.setPopup({popup: "popup.html"});
        browser.browserAction.setIcon({path: {"16": "/img/a.png", "32": "img/b.png"}});
        0
      ''');
      await eventually(
        () async => actions.stateFor(extension.uuid).popup == 'popup.html',
      );

      expect(actions.stateFor(extension.uuid).badgeText, '12');
      expect(actions.stateFor(extension.uuid, tabId: 7).badgeText, '3');
      expect(actions.stateFor(extension.uuid, tabId: 8).badgeText, '12');
      expect(actions.stateFor(extension.uuid).badgeBackground, [
        255,
        0,
        0,
        255,
      ]);
      expect(actions.stateFor(extension.uuid).title, 'Blocked');
      expect(actions.stateFor(extension.uuid).iconPath, 'img/b.png');
      expect(
        await page.world.run('browser.browserAction.getBadgeText({tabId: 7})'),
        '3',
      );
      expect(await page.world.run('browser.browserAction.isEnabled({})'), true);
    });

    test('action is the same button', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await page.world.run('browser.action.setBadgeText({text: "9"})');
      expect(actions.stateFor(extension.uuid).badgeText, '9');
    });

    test('a click reaches the extension', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await page.world.run(
        'globalThis.clicks = []; browser.browserAction.onClicked.addListener((tab) => clicks.push(tab.id)); 0',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      ActionApi.notifyClicked(host, extension, {'id': 5});
      await eventually(
        () async => ((await page.world.run('clicks.length')) as int) == 1,
      );
      expect(await page.world.run('clicks'), [5]);
    });
  });

  group('menus', () {
    test('keeps the items an extension makes', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      await page.world.run(
        'browser.menus.create({id: "a", title: "A", contexts: ["page"]}); browser.menus.create({id: "b", title: "B", parentId: "a"}); 0',
      );
      await eventually(() async => menus.itemsOf(extension.uuid).length == 2);
      await page.world.run('browser.menus.update("a", {title: "A2"})');
      expect(menus.itemsOf(extension.uuid).first['title'], 'A2');

      await page.world.run('browser.menus.remove("a")');
      expect(
        menus.itemsOf(extension.uuid),
        isEmpty,
        reason: 'children go with their parent',
      );
    });
  });

  group('alarms', () {
    test('fire, get, and clear', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await page.world.run('''
        globalThis.fired = [];
        browser.alarms.onAlarm.addListener((a) => fired.push(a.name));
        browser.alarms.create("soon", {when: Date.now() + 80});
        browser.alarms.create("later", {delayInMinutes: 60});
        0
      ''');

      await eventually(
        () async => ((await page.world.run('fired.length')) as int) == 1,
      );
      expect(await page.world.run('fired'), ['soon']);
      expect(
        await page.world.run(
          'browser.alarms.getAll().then((a) => a.map((x) => x.name))',
        ),
        ['later'],
      );
      expect(await page.world.run('browser.alarms.clear("later")'), true);
      expect(
        await page.world.run('browser.alarms.getAll().then((a) => a.length)'),
        0,
      );
    });
  });

  group('permissions and commands', () {
    test('permissions answer from what was granted', () async {
      final extension = await install(
        permissions: const ['storage', 'tabs', 'https://example.com/*'],
      );
      await host.start();
      final page = await open(extension, isPage: true);

      expect(
        await page.world.run(
          'browser.permissions.contains({permissions: ["tabs"]})',
        ),
        true,
      );
      expect(
        await page.world.run(
          'browser.permissions.contains({permissions: ["history"]})',
        ),
        false,
      );
      expect(
        await page.world.run(
          'browser.permissions.contains({origins: ["https://example.com/a"]})',
        ),
        true,
        reason: 'a URL is a pattern too, and this one is covered',
      );
      expect(
        await page.world.run(
          'browser.permissions.contains({origins: ["https://example.com/*"]})',
        ),
        true,
      );
      expect(
        await page.world.run(
          'browser.permissions.request({permissions: ["history"]})',
        ),
        false,
      );
      final all = await page.world.run('browser.permissions.getAll()') as Map;
      expect(all['permissions'], contains('tabs'));
    });

    test('commands list the manifest\'s shortcuts', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      expect(
        await page.world.run('browser.commands.getAll().then((c) => c.length)'),
        0,
      );
    });
  });

  group('dns', () {
    test('resolves a name', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      final result =
          await page.world.run('browser.dns.resolve("localhost")') as Map;
      expect(result['addresses'], isNotEmpty);
      await expectLater(
        page.world.run('browser.dns.resolve("does-not-exist.invalid")'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('contentScripts.register', () {
    test('adds a script to the state the processes run', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);

      final before = transport.states.length;
      await page.world.run('''
        browser.contentScripts.register({
          matches: ["https://*.example.com/*"],
          js: [{code: "console.log(1)"}, {file: "content.js"}],
          css: [{code: "a { color: red }"}],
          runAt: "document_start",
          allFrames: true,
        }).then((h) => { globalThis.handle = h; })
      ''');
      await eventually(() async => transport.states.length > before);

      Map<String, Object?> dynamic() {
        final state = jsonDecode(transport.states.last) as Map<String, Object?>;
        final entry =
            (state['extensions']! as List).single as Map<String, Object?>;
        return (entry['contentScripts']! as List).last as Map<String, Object?>;
      }

      final script = dynamic();
      expect(script['matches'], ['https://*.example.com/*']);
      expect(script['runAt'], 'document_start');
      expect(script['allFrames'], isTrue);
      expect((script['js']! as List).map((j) => (j as Map)['source']), [
        'console.log(1)',
        '// content',
      ]);
      expect((script['css']! as List).single['source'], 'a { color: red }');

      final withIt = transport.states.length;
      await page.world.run('handle.unregister()');
      await eventually(() async => transport.states.length > withIt);
      final remaining =
          ((jsonDecode(transport.states.last) as Map)['extensions'] as List)
                  .single['contentScripts']
              as List;
      expect(
        remaining.any((s) => (s as Map)['runAt'] == 'document_start'),
        isFalse,
      );
    });
  });

  group('webRequest', () {
    Future<void> listen(NodeWorld page, String code) async {
      await page.run(code);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    const details = {
      'requestId': '1',
      'url': 'https://ads.example/banner.js',
      'method': 'GET',
      'tabId': 5,
      'type': 'script',
      'frameId': 0,
    };

    test('a blocking listener cancels a request', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await listen(page.world, '''
        browser.webRequest.onBeforeRequest.addListener(
          (d) => ({cancel: d.url.includes("ads.")}),
          {urls: ["<all_urls>"]}, ["blocking"]);
      ''');

      final blocked = await webRequest.dispatch(
        'webRequest.onBeforeRequest',
        details,
      );
      expect(blocked.cancel, isTrue);

      final allowed = await webRequest.dispatch('webRequest.onBeforeRequest', {
        ...details,
        'url': 'https://fine.example/a.js',
      });
      expect(allowed.changesAnything, isFalse);
    });

    test('a listener can redirect', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await listen(
        page.world,
        'browser.webRequest.onBeforeRequest.addListener(() => ({redirectUrl: "https://x.example/r"}), {urls: ["<all_urls>"]}, ["blocking"])',
      );

      final verdict = await webRequest.dispatch(
        'webRequest.onBeforeRequest',
        details,
      );
      expect(verdict.redirectUrl, 'https://x.example/r');
      expect(verdict.cancel, isFalse);
    });

    test('filters decide which requests a listener hears about', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await listen(
        page.world,
        'browser.webRequest.onBeforeRequest.addListener(() => ({cancel: true}), {urls: ["https://only.example/*"], types: ["image"]}, ["blocking"])',
      );

      expect(
        (await webRequest.dispatch(
          'webRequest.onBeforeRequest',
          details,
        )).cancel,
        isFalse,
        reason: 'wrong url and type',
      );
      expect(
        (await webRequest.dispatch('webRequest.onBeforeRequest', {
          ...details,
          'url': 'https://only.example/a.png',
          'type': 'image',
        })).cancel,
        isTrue,
      );
      expect(
        (await webRequest.dispatch('webRequest.onBeforeRequest', {
          ...details,
          'url': 'https://only.example/a.png',
          'type': 'script',
        })).cancel,
        isFalse,
        reason: 'wrong type',
      );
    });

    test('a listener without "blocking" cannot cancel', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await listen(
        page.world,
        'browser.webRequest.onBeforeRequest.addListener(() => ({cancel: true}), {urls: ["<all_urls>"]})',
      );

      expect(
        (await webRequest.dispatch(
          'webRequest.onBeforeRequest',
          details,
        )).cancel,
        isFalse,
      );
    });

    test('an extension without host access sees nothing', () async {
      final extension = await install(
        permissions: const ['storage', 'webRequest', 'webRequestBlocking'],
      );
      await host.start();
      final page = await open(extension, isPage: true);
      await listen(
        page.world,
        'browser.webRequest.onBeforeRequest.addListener(() => ({cancel: true}), {urls: ["<all_urls>"]}, ["blocking"])',
      );

      expect(
        (await webRequest.dispatch(
          'webRequest.onBeforeRequest',
          details,
        )).cancel,
        isFalse,
      );
    });

    test(
      'observers are told, and a slow blocking listener does not hold the request forever',
      () async {
        final extension = await install();
        await host.start();
        final page = await open(extension, isPage: true);
        await listen(page.world, '''
        globalThis.seen = [];
        browser.webRequest.onCompleted.addListener((d) => seen.push(d.url), {urls: ["<all_urls>"]});
      ''');

        webRequest.observe('webRequest.onCompleted', details);
        await eventually(
          () async => ((await page.world.run('seen.length')) as int) == 1,
        );
        expect(await page.world.run('seen'), ['https://ads.example/banner.js']);
      },
    );

    test('intercept answers in the form the network layer wants', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await listen(page.world, '''
        browser.webRequest.onBeforeRequest.addListener(
          (d) => d.url.includes("ads.") ? {cancel: true} : d.url.includes("swap") ? {redirectUrl: "https://x/y"} : undefined,
          {urls: ["<all_urls>"]}, ["blocking"]);
      ''');

      expect(jsonDecode(await webRequest.intercept(details)), {'cancel': true});
      expect(
        jsonDecode(
          await webRequest.intercept({
            ...details,
            'url': 'https://swap.example/a',
          }),
        ),
        {'redirectUrl': 'https://x/y'},
      );
      expect(
        jsonDecode(
          await webRequest.intercept({
            ...details,
            'url': 'https://fine.example/a',
          }),
        ),
        isEmpty,
      );
    });

    test('the request a listener sees has the details it needs', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      await listen(page.world, '''
        globalThis.seen = null;
        browser.webRequest.onBeforeRequest.addListener((d) => { seen = d; }, {urls: ["<all_urls>"]}, ["blocking"]);
      ''');

      await webRequest.intercept({
        ...details,
        'documentUrl': 'https://example.com/',
      });
      final seen = await page.world.run('seen') as Map;
      expect(seen['url'], 'https://ads.example/banner.js');
      expect(seen['tabId'], 5);
      expect(seen['type'], 'script');
      expect(seen['documentUrl'], 'https://example.com/');
      expect(seen['timeStamp'], isA<num>());
    });

    test('knows whether anything wants to block', () async {
      final extension = await install();
      await host.start();
      final page = await open(extension, isPage: true);
      expect(webRequest.wantsToBlock('webRequest.onBeforeRequest'), isFalse);

      await listen(
        page.world,
        'browser.webRequest.onBeforeRequest.addListener(() => {}, {urls: ["<all_urls>"]}, ["blocking"])',
      );
      expect(webRequest.wantsToBlock('webRequest.onBeforeRequest'), isTrue);
      expect(webRequest.isWanted('webRequest.onCompleted'), isFalse);
    });
  });
}

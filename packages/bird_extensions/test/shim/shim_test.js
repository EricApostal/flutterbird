// Runs the shim against fake natives in a separate V8 context, the way the
// engine runs it in an extension world. Run with: node --test test/shim
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '../../lib/src/shim/browser_shim.js'), 'utf8');

function createWorld(initOverrides = {}, documentOverrides = {}) {
  const sent = [];
  const phases = [];
  const domListeners = {};
  const appended = [];
  let receiver = null;

  const document = {
    readyState: 'loading',
    documentElement: {},
    head: { appendChild: (node) => appended.push(node) },
    addEventListener(type, listener) {
      (domListeners[type] = domListeners[type] || []).push(listener);
    },
    createElement(tag) {
      return { tag, textContent: '' };
    },
    adoptedStyleSheets: [],
    ...documentOverrides,
  };

  const init = {
    id: 'ext@test',
    baseUrl: 'moz-extension://abc/',
    manifest: { name: 'Example', version: '1.0' },
    messages: {
      greeting: { message: 'Hello $1, you owe $$5 and $2' },
      plain: { message: 'Plain' },
    },
    uiLanguage: 'fr',
    ...initOverrides,
  };
  delete init.__page;

  const context = vm.createContext({
    __bird_init: init,
    __bird_send: (text) => sent.push(JSON.parse(text)),
    __bird_set_receiver: (fn) => {
      receiver = fn;
    },
    __bird_phase: (name) => phases.push(name),
    document,
    setTimeout,
    console: { error() {} },
    ...(initOverrides.__page ? { location: { protocol: 'moz-extension:' } } : {}),
  });
  vm.runInContext(source, context);

  return {
    sent,
    phases,
    appended,
    document,
    run: (code) => vm.runInContext(code, context),
    deliver: (message) => receiver(JSON.stringify(message)),
    fire: (type) => (domListeners[type] || []).forEach((listener) => listener()),
    listenersFor: (type) => (domListeners[type] || []).length,
    // The browser answering the call with this id.
    reply: (id, body) => receiver(JSON.stringify({ reply: id, ...body })),
    tick: () => new Promise((resolve) => setTimeout(resolve, 5)),
  };
}

test('defines browser and chrome, and removes the natives from the global', () => {
  const world = createWorld();
  assert.equal(world.run('typeof browser'), 'object');
  assert.equal(world.run('typeof chrome'), 'object');
  for (const name of ['__bird_init', '__bird_send', '__bird_set_receiver', '__bird_phase']) {
    assert.equal(world.run(`typeof ${name}`), 'undefined', name);
  }
});

test('runtime basics', () => {
  const world = createWorld();
  assert.equal(world.run('browser.runtime.id'), 'ext@test');
  assert.equal(world.run('browser.runtime.getURL("/a/b.png")'), 'moz-extension://abc/a/b.png');
  assert.equal(world.run('browser.extension.getURL("c.js")'), 'moz-extension://abc/c.js');
  assert.equal(world.run('browser.runtime.getManifest().name'), 'Example');

  // The manifest is a copy: changing it must not change what others read.
  world.run('browser.runtime.getManifest().name = "changed"');
  assert.equal(world.run('browser.runtime.getManifest().name'), 'Example');
});

test('a call is sent with an id and resolves with its reply', async () => {
  const world = createWorld();
  const promise = world.run('browser.storage.local.get("key")');

  assert.deepEqual(world.sent, [{ id: 1, ns: 'storage', method: 'get', args: ['local', 'key'] }]);
  world.reply(1, { result: { key: 'value' } });
  // Objects made inside the context have their own Object prototype, so compare by value.
  assert.deepEqual(JSON.parse(JSON.stringify(await promise)), { key: 'value' });
});

test('get with no keys asks for everything', () => {
  const world = createWorld();
  world.run('browser.storage.sync.get()');
  assert.deepEqual(world.sent[0].args, ['sync', null]);
});

test('a failed call rejects with an Error carrying the message', async () => {
  const world = createWorld();
  const promise = world.run('browser.storage.local.set({a: 1})');
  world.reply(1, { error: { message: 'quota exceeded' } });

  await assert.rejects(promise, (error) => error.message === 'quota exceeded');
});

test('calls get distinct ids and replies are matched by id', async () => {
  const world = createWorld();
  const first = world.run('browser.storage.local.get("a")');
  const second = world.run('browser.storage.local.get("b")');
  assert.deepEqual(world.sent.map((m) => m.id), [1, 2]);

  world.reply(2, { result: 'two' });
  world.reply(1, { result: 'one' });
  assert.equal(await first, 'one');
  assert.equal(await second, 'two');
});

test('a reply nobody is waiting for is ignored', () => {
  const world = createWorld();
  world.reply(99, { result: 1 });
});

test('sendMessage normalizes its arguments', () => {
  const world = createWorld();
  world.run('browser.runtime.sendMessage({hello: 1})');
  world.run('browser.runtime.sendMessage("ext@test", {hello: 2})');
  world.run('browser.runtime.sendMessage({hello: 3}, {includeTlsChannelId: true})');
  world.run('browser.runtime.sendMessage("ext@test", {hello: 4}, {})');
  world.run('browser.runtime.sendMessage("just a string")');

  assert.deepEqual(world.sent.map((m) => m.args), [
    [{ hello: 1 }, null],
    [{ hello: 2 }, null],
    [{ hello: 3 }, { includeTlsChannelId: true }],
    [{ hello: 4 }, {}],
    ['just a string', null],
  ]);
});

test('messaging another extension is refused', async () => {
  const world = createWorld();
  await assert.rejects(
    world.run('browser.runtime.sendMessage("other@test", {x: 1})'),
    /other extensions/,
  );
  assert.equal(world.sent.length, 0);
});

test('events: add, has, remove', () => {
  const world = createWorld();
  world.run('globalThis.fn = function () {}; browser.storage.onChanged.addListener(fn);');
  assert.equal(world.run('browser.storage.onChanged.hasListener(fn)'), true);
  assert.equal(world.run('browser.storage.onChanged.hasListeners()'), true);

  // Adding twice does not register twice.
  world.run('browser.storage.onChanged.addListener(fn)');
  world.run('browser.storage.onChanged.removeListener(fn)');
  assert.equal(world.run('browser.storage.onChanged.hasListener(fn)'), false);
});

test('a plain event reaches its listeners with its arguments', () => {
  const world = createWorld();
  world.run('globalThis.seen = []; browser.storage.onChanged.addListener((c, a) => seen.push([c, a]));');
  world.deliver({ event: 'storage.onChanged', args: [{ k: { newValue: 1 } }, 'local'] });
  assert.deepEqual(JSON.parse(world.run('JSON.stringify(seen)')), [[{ k: { newValue: 1 } }, 'local']]);
});

test('a throwing listener does not stop the others', () => {
  const world = createWorld();
  world.run(`
    globalThis.seen = 0;
    browser.storage.onChanged.addListener(() => { throw new Error('boom'); });
    browser.storage.onChanged.addListener(() => { seen++; });
  `);
  world.deliver({ event: 'storage.onChanged', args: [] });
  assert.equal(world.run('seen'), 1);
});

function respondCalls(world) {
  return world.sent.filter((m) => m.ns === 'bird' && m.method === 'respond');
}

test('onMessage: sendResponse answers once with the value', () => {
  const world = createWorld();
  world.run('browser.runtime.onMessage.addListener((m, s, sendResponse) => { sendResponse({got: m}); });');
  world.deliver({ event: 'runtime.onMessage', args: ['hi', { id: 'ext@test' }], token: 5 });

  assert.deepEqual(respondCalls(world).map((m) => m.args), [[5, { handled: true, value: { got: 'hi' } }]]);
});

test('onMessage: a returned promise is the answer', async () => {
  const world = createWorld();
  world.run('browser.runtime.onMessage.addListener(async (m) => "later " + m);');
  world.deliver({ event: 'runtime.onMessage', args: ['x', {}], token: 6 });

  assert.equal(respondCalls(world).length, 0, 'not answered until the promise settles');
  await world.tick();
  assert.deepEqual(respondCalls(world).map((m) => m.args), [[6, { handled: true, value: 'later x' }]]);
});

test('onMessage: a rejected promise answers with an error', async () => {
  const world = createWorld();
  world.run('browser.runtime.onMessage.addListener(async () => { throw new Error("nope"); });');
  world.deliver({ event: 'runtime.onMessage', args: ['x', {}], token: 7 });
  await world.tick();
  assert.deepEqual(respondCalls(world).map((m) => m.args), [[7, { handled: true, error: { message: 'nope' } }]]);
});

test('onMessage: returning true keeps the channel open for a later sendResponse', async () => {
  const world = createWorld();
  world.run(`
    browser.runtime.onMessage.addListener((m, s, sendResponse) => {
      setTimeout(() => sendResponse('async'), 1);
      return true;
    });
  `);
  world.deliver({ event: 'runtime.onMessage', args: ['x', {}], token: 8 });
  assert.equal(respondCalls(world).length, 0);
  await world.tick();
  assert.deepEqual(respondCalls(world).map((m) => m.args), [[8, { handled: true, value: 'async' }]]);
});

test('onMessage: no listener, or none that answers, reports unhandled', () => {
  const world = createWorld();
  world.deliver({ event: 'runtime.onMessage', args: ['x', {}], token: 9 });
  world.run('browser.runtime.onMessage.addListener(() => {});');
  world.deliver({ event: 'runtime.onMessage', args: ['x', {}], token: 10 });

  assert.deepEqual(respondCalls(world).map((m) => m.args), [
    [9, { handled: false }],
    [10, { handled: false }],
  ]);
});

test('onMessage: only the first answer counts', () => {
  const world = createWorld();
  world.run(`
    browser.runtime.onMessage.addListener((m, s, send) => send('first'));
    browser.runtime.onMessage.addListener((m, s, send) => send('second'));
  `);
  world.deliver({ event: 'runtime.onMessage', args: ['x', {}], token: 11 });
  assert.deepEqual(respondCalls(world).map((m) => m.args), [[11, { handled: true, value: 'first' }]]);
});

test('onMessage: a throwing listener does not stop an answering one', () => {
  const world = createWorld();
  world.run(`
    browser.runtime.onMessage.addListener(() => { throw new Error('x'); });
    browser.runtime.onMessage.addListener((m, s, send) => send('ok'));
  `);
  world.deliver({ event: 'runtime.onMessage', args: ['x', {}], token: 12 });
  assert.deepEqual(respondCalls(world).map((m) => m.args), [[12, { handled: true, value: 'ok' }]]);
});

test('i18n.getMessage substitutes, escapes and ignores case', () => {
  const world = createWorld();
  assert.equal(world.run('browser.i18n.getMessage("greeting", ["Ann", "bye"])'), 'Hello Ann, you owe $5 and bye');
  assert.equal(world.run('browser.i18n.getMessage("GREETING", "Bo")'), 'Hello Bo, you owe $5 and ');
  assert.equal(world.run('browser.i18n.getMessage("plain")'), 'Plain');
  assert.equal(world.run('browser.i18n.getMessage("missing")'), '');
  assert.equal(world.run('browser.i18n.getUILanguage()'), 'fr');
});

test('chrome flavour: a callback receives the result, and no promise is returned', async () => {
  const world = createWorld();
  world.run('globalThis.result = "unset"; globalThis.ret = chrome.storage.local.get("k", (v) => { result = v; });');
  assert.equal(world.run('ret'), undefined);
  world.reply(1, { result: { k: 1 } });
  await world.tick();
  assert.deepEqual(JSON.parse(world.run('JSON.stringify(result)')), { k: 1 });
});

test('chrome flavour: without a callback it returns the promise', async () => {
  const world = createWorld();
  const promise = world.run('chrome.storage.local.get("k")');
  world.reply(1, { result: 'v' });
  assert.equal(await promise, 'v');
});

test('chrome flavour: a failure sets lastError for the callback only', async () => {
  const world = createWorld();
  world.run(`
    globalThis.seenError = null;
    chrome.storage.local.set({a: 1}, () => { seenError = chrome.runtime.lastError && chrome.runtime.lastError.message; });
  `);
  world.reply(1, { error: { message: 'bad' } });
  await world.tick();
  assert.equal(world.run('seenError'), 'bad');
  assert.equal(world.run('chrome.runtime.lastError'), undefined);
});

test('chrome and browser share their events', () => {
  const world = createWorld();
  assert.equal(world.run('chrome.runtime.onMessage === browser.runtime.onMessage'), true);
  assert.equal(world.run('chrome.runtime.id'), 'ext@test');
});

test('document_end and document_idle are requested after the document parses', async () => {
  const world = createWorld();
  // One for the content script phases, one that reports the event to webNavigation.
  assert.equal(world.listenersFor('DOMContentLoaded'), 2);
  assert.deepEqual(world.phases, []);

  world.fire('DOMContentLoaded');
  assert.deepEqual(world.phases, ['document_end']);
  await world.tick();
  assert.deepEqual(world.phases, ['document_end', 'document_idle']);
});

test('a document that has already parsed requests both phases at once', async () => {
  const world = createWorld({}, { readyState: 'complete' });
  assert.equal(world.listenersFor('DOMContentLoaded'), 0);
  assert.deepEqual(world.phases, ['document_end']);
  assert.deepEqual(world.sent.filter((m) => m.method === 'documentEvent').map((m) => m.args), [
    ['DOMContentLoaded'],
    ['load'],
  ]);
  await world.tick();
  assert.deepEqual(world.phases, ['document_end', 'document_idle']);
});

test('css is adopted when constructable stylesheets exist', () => {
  class FakeSheet {
    replaceSync(css) {
      this.css = css;
    }
  }
  const world = createWorld();
  world.run('globalThis.CSSStyleSheet = ' + FakeSheet.toString());
  world.run('__bird_insert_css("a { color: red }")');
  assert.equal(world.document.adoptedStyleSheets.length, 1);
  assert.equal(world.document.adoptedStyleSheets[0].css, 'a { color: red }');
});

test('css falls back to a style element', () => {
  const world = createWorld();
  world.run('__bird_insert_css("b { color: blue }")');
  assert.equal(world.appended.length, 1);
  assert.equal(world.appended[0].tag, 'style');
  assert.equal(world.appended[0].textContent, 'b { color: blue }');
});

// ---------------------------------------------------------------- pages, ports, tracked events

const page = (extra = {}) => createWorld({ __page: true, uuid: 'u1', ...extra });

test('content scripts get a small API; extension pages get the rest', () => {
  const contentScript = createWorld();
  for (const name of ['tabs', 'windows', 'webRequest', 'browserAction', 'menus', 'alarms', 'privacy']) {
    assert.equal(contentScript.run(`typeof browser.${name}`), 'undefined', name);
  }
  assert.equal(contentScript.run('typeof browser.runtime.connect'), 'function');

  const extensionPage = page();
  for (const name of ['tabs', 'windows', 'webNavigation', 'webRequest', 'browserAction', 'action', 'menus',
    'contextMenus', 'alarms', 'commands', 'permissions', 'privacy', 'dns', 'contentScripts']) {
    assert.equal(extensionPage.run(`typeof browser.${name}`), 'object', name);
  }
});

test('the browser identifies as Firefox, because that is the API on offer', async () => {
  const world = page();
  const info = JSON.parse(JSON.stringify(await world.run('browser.runtime.getBrowserInfo()')));
  assert.equal(info.name, 'Firefox');
  assert.ok(parseInt(info.version, 10) >= 115);
});

test('tracked events tell the browser when listeners come and go', () => {
  const world = page();
  const sentAbout = () => world.sent.filter((m) => m.ns === 'events').map((m) => [m.method, ...m.args]);

  world.run('globalThis.a = () => {}; globalThis.b = () => {};');
  world.run('browser.tabs.onUpdated.addListener(a); browser.tabs.onUpdated.addListener(b);');
  assert.deepEqual(sentAbout(), [['addListener', 'tabs.onUpdated', []]], 'only the first listener is announced');

  world.run('browser.tabs.onUpdated.removeListener(a);');
  assert.equal(sentAbout().length, 1, 'one listener is still left');
  world.run('browser.tabs.onUpdated.removeListener(b);');
  assert.deepEqual(sentAbout().at(-1), ['removeListener', 'tabs.onUpdated']);
});

test('webRequest listeners send their filter and options with them', () => {
  const world = page();
  world.run(`browser.webRequest.onBeforeRequest.addListener(() => {}, {urls: ["<all_urls>"], types: ["script"]}, ["blocking"]);`);
  const call = world.sent.find((m) => m.ns === 'events');
  assert.deepEqual(JSON.parse(JSON.stringify(call.args)), [
    'webRequest.onBeforeRequest',
    [{ urls: ['<all_urls>'], types: ['script'] }, ['blocking']],
  ]);
});

function answers(world) {
  return world.sent.filter((m) => m.ns === 'bird' && m.method === 'respond').map((m) => m.args);
}

test('a blocking webRequest listener answers by returning', () => {
  const world = page();
  world.run('browser.webRequest.onBeforeRequest.addListener((details) => ({cancel: details.url.includes("ads")}), {urls: ["<all_urls>"]}, ["blocking"]);');

  world.deliver({ event: 'webRequest.onBeforeRequest', args: [{ url: 'https://ads.example/x' }], token: 3 });
  world.deliver({ event: 'webRequest.onBeforeRequest', args: [{ url: 'https://ok.example/x' }], token: 4 });

  assert.deepEqual(JSON.parse(JSON.stringify(answers(world))), [
    [3, { handled: true, value: { cancel: true } }],
    [4, { handled: true, value: { cancel: false } }],
  ]);
});

test('a blocking listener may answer with a promise, and one that returns nothing is unhandled', async () => {
  const world = page();
  world.run(`
    browser.webRequest.onBeforeRequest.addListener(async () => ({redirectUrl: "https://x/y"}), {urls: ["<all_urls>"]}, ["blocking"]);
  `);
  world.deliver({ event: 'webRequest.onBeforeRequest', args: [{}], token: 5 });
  await world.tick();
  assert.deepEqual(JSON.parse(JSON.stringify(answers(world))), [[5, { handled: true, value: { redirectUrl: 'https://x/y' } }]]);

  const quiet = page();
  quiet.run('browser.webRequest.onBeforeRequest.addListener(() => {}, {urls: ["<all_urls>"]}, ["blocking"]);');
  quiet.deliver({ event: 'webRequest.onBeforeRequest', args: [{}], token: 6 });
  assert.deepEqual(JSON.parse(JSON.stringify(answers(quiet))), [[6, { handled: false }]]);
});

test('runtime.connect makes a port the browser is told about', () => {
  const world = page();
  const port = world.run('globalThis.port = browser.runtime.connect({name: "popup"}); port.name');
  assert.equal(port, 'popup');

  const connect = world.sent.find((m) => m.ns === 'runtime' && m.method === 'connect');
  assert.equal(connect.args[1], 'popup');
  assert.match(connect.args[0], /^u1:/);
});

test('a port carries messages both ways and disconnects', () => {
  const world = page();
  world.run('globalThis.port = browser.runtime.connect({name: "p"}); globalThis.got = []; globalThis.gone = 0;');
  world.run('port.onMessage.addListener((m) => got.push(m)); port.onDisconnect.addListener(() => gone++);');
  const portId = world.sent.find((m) => m.method === 'connect').args[0];

  world.run('port.postMessage({hello: 1})');
  assert.deepEqual(JSON.parse(JSON.stringify(world.sent.find((m) => m.method === 'portPost').args)), [portId, { hello: 1 }]);

  world.deliver({ event: 'bird.portMessage', args: [portId, { reply: 2 }] });
  assert.deepEqual(JSON.parse(world.run('JSON.stringify(got)')), [{ reply: 2 }]);

  world.deliver({ event: 'bird.portDisconnect', args: [portId] });
  assert.equal(world.run('gone'), 1);
  assert.throws(() => world.run('port.postMessage(1)'), /disconnected port/);

  // Messages for a port that is gone are ignored.
  world.deliver({ event: 'bird.portMessage', args: [portId, 'late'] });
  assert.equal(world.run('got.length'), 1);
});

test('closing a port tells the browser once', () => {
  const world = page();
  world.run('globalThis.port = browser.runtime.connect({name: "p"}); port.disconnect(); port.disconnect();');
  assert.equal(world.sent.filter((m) => m.method === 'portDisconnect').length, 1);
});

test('a refused connect disconnects the port with the reason', async () => {
  const world = page();
  world.run('globalThis.port = browser.runtime.connect({name: "p"}); globalThis.why = null; port.onDisconnect.addListener((p) => { why = p.error && p.error.message; });');
  const id = world.sent.find((m) => m.method === 'connect').id;
  world.reply(id, { error: { message: 'Could not establish connection.' } });
  await world.tick();
  assert.equal(world.run('why'), 'Could not establish connection.');
});

test('an incoming connection becomes a port for onConnect listeners', () => {
  const world = page();
  world.run('globalThis.seen = []; browser.runtime.onConnect.addListener((p) => { seen.push([p.name, p.sender.id]); p.onMessage.addListener((m) => p.postMessage({echo: m})); });');

  world.deliver({ event: 'runtime.onConnect', args: [{ portId: 'remote:1', name: 'cs', sender: { id: 'ext@test' } }] });
  assert.deepEqual(JSON.parse(world.run('JSON.stringify(seen)')), [['cs', 'ext@test']]);

  world.deliver({ event: 'bird.portMessage', args: ['remote:1', 'ping'] });
  const post = world.sent.find((m) => m.method === 'portPost');
  assert.deepEqual(JSON.parse(JSON.stringify(post.args)), ['remote:1', { echo: 'ping' }]);
});

test('a connection nobody listens for is declined', () => {
  const world = page();
  world.deliver({ event: 'runtime.onConnect', args: [{ portId: 'remote:2', name: 'x', sender: {} }] });
  assert.deepEqual(world.sent.find((m) => m.method === 'portDisconnect').args, ['remote:2']);
});

test('tabs.connect names the tab and frame', () => {
  const world = page();
  world.run('browser.tabs.connect(7, {name: "cs", frameId: 0})');
  const call = world.sent.find((m) => m.ns === 'tabs' && m.method === 'connect');
  assert.deepEqual(JSON.parse(JSON.stringify(call.args.slice(1))), [7, 'cs', 0]);
});

test('bird.eval runs code and answers with its result', async () => {
  const world = createWorld();
  world.deliver({ event: 'bird.eval', args: ['1 + 2'], token: 9 });
  world.deliver({ event: 'bird.eval', args: ['Promise.resolve("later")'], token: 10 });
  world.deliver({ event: 'bird.eval', args: ['throw new Error("bad")'], token: 11 });
  world.deliver({ event: 'bird.eval', args: ['undefined'], token: 12 });
  await world.tick();

  const byToken = Object.fromEntries(answers(world).map(([token, body]) => [token, JSON.parse(JSON.stringify(body))]));
  assert.deepEqual(byToken[9], { handled: true, value: 3 });
  assert.deepEqual(byToken[10], { handled: true, value: 'later' });
  assert.deepEqual(byToken[11], { handled: true, error: { message: 'bad' } });
  assert.deepEqual(byToken[12], { handled: true, value: null });
});

test('menus.create returns its id at once and tells the browser', () => {
  const world = page();
  assert.equal(world.run('browser.menus.create({title: "x", id: "mine"})'), 'mine');
  const generated = world.run('browser.menus.create({title: "y"})');
  assert.match(generated, /^menu-/);
  const creates = world.sent.filter((m) => m.ns === 'menus' && m.method === 'create');
  assert.deepEqual(creates.map((m) => m.args[0].id), ['mine', generated]);
});

test('privacy settings can be read and set without effect', async () => {
  const world = page();
  const policy = JSON.parse(JSON.stringify(await world.run('browser.privacy.network.webRTCIPHandlingPolicy.get({})')));
  assert.equal(policy.value, 'default');
  await world.run('browser.privacy.network.webRTCIPHandlingPolicy.set({value: "disable_non_proxied_udp"})');
});

test('constants extensions read exist', () => {
  const world = page();
  assert.equal(world.run('browser.windows.WINDOW_ID_NONE'), -1);
  assert.equal(world.run('browser.windows.WINDOW_ID_CURRENT'), -2);
  assert.equal(world.run('browser.tabs.TAB_ID_NONE'), -1);
  assert.equal(world.run('browser.webRequest.ResourceType.XMLHTTPREQUEST'), 'xmlhttprequest');
  assert.equal(world.run('browser.webRequest.MAX_HANDLER_BEHAVIOR_CHANGED_CALLS_PER_10_MINUTES'), 20);
});

test('contentScripts.register resolves to something that can be unregistered', async () => {
  const world = page();
  const registered = world.run('browser.contentScripts.register({matches: ["<all_urls>"], js: [{code: "1"}]})');
  world.reply(world.sent.find((m) => m.ns === 'contentScripts').id, { result: 'reg-1' });
  await registered;

  world.run('globalThis.handle = null; browser.contentScripts.register({matches: ["<all_urls>"]}).then((h) => { handle = h; })');
  world.reply(world.sent.filter((m) => m.method === 'register')[1].id, { result: 'reg-2' });
  await world.tick();
  world.run('handle.unregister()');
  const unregister = world.sent.find((m) => m.method === 'unregister');
  assert.deepEqual(JSON.parse(JSON.stringify(unregister.args)), ['reg-2']);
});

test('dom.openOrClosedShadowRoot returns an open shadow root, else null', () => {
  const world = createWorld();
  assert.equal(world.run('browser.dom.openOrClosedShadowRoot({shadowRoot: "root"})'), 'root');
  assert.equal(world.run('browser.dom.openOrClosedShadowRoot({})'), null);
  assert.equal(world.run('browser.dom.openOrClosedShadowRoot(null)'), null);
});

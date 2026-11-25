# Extensions in FlutterBird

Goal: install and run Firefox (WebExtensions) add-ons from addons.mozilla.org.
Target behaviour is **Firefox's**, as documented on MDN and defined by the
schemas in <https://github.com/w3c/webextensions/tree/main/interfaces/firefox>.
The W3C WECG spec text itself covers only packaging, content scripts, match
patterns and Alarms; every other API is de facto, so the Firefox JSON schemas
are the source of truth and the bindings should be generated from them.

Decisions made with the user:

- **Trust AMO.** No signature verification of `.xpi` files. The installer does
  check the SHA-256 that the AMO API publishes (integrity, not authenticity).
- **Firefox compatibility is the goal**, including blocking `webRequest`,
  `filterResponseData`, containers, `dns`. "Skip because hard" is not a
  reason; scope is decided by what Firefox extensions use.
- Never build flutterbird to verify (see project memory); verify statically,
  and use `dart test` in this package, which is pure Dart.

## Status

| Milestone | State |
|---|---|
| M1 Installer, registry, manifest, permissions, CLI | **done**, tested |
| M2a Content scripts in isolated worlds, string bridge, state push | written; **C++ uncompiled** |
| M2b `moz-extension://` origin and files, extension pages, background pages | written; **C++ uncompiled** |
| M3 Dart APIs: `runtime` (messaging, ports), `storage`, `tabs`, `windows`, `webNavigation`, `browserAction`/`action`, `menus`, `alarms`, `commands`, `permissions`, `dns`, `contentScripts` | **done in Dart, tested** (170 tests) |
| M4a `webRequest`: blocking `onBeforeRequest` and `onBeforeSendHeaders` (cancel, redirect, header set) | Dart tested; **engine hook uncompiled** |
| M4b `webRequest`: `onHeadersReceived`, observational events, `filterResponseData`, `declarativeNetRequest` | not started |
| M5 Containers, `proxy`, `browsingData`, `privacy` (stubs only), `find`, `webNavigation` for pages without a content script | not started |
| M6 App UI: add-ons panel, toolbar buttons with badges, popups | written, analyzed; **not run** |

### uBlock Origin

`ublock-origin` installs from AMO (verified against the live API: a 6 MB package, `sha256` checked),
its manifest parses with no warnings, the engine state built from it is correct (122 KB: three
content script groups, its web accessible rule, 328 localized messages), and every
`browser.<namespace>.<member>` its scripts reference exists in the shim. What is **not** known is
whether it runs: that needs the engine built, because its background page runs in Ladybird.

What it will still lack when it runs: `onHeadersReceived` (CSP and header edits), `filterResponseData`
(HTML filtering), `onCompleted` and the other observational request events (its logger),
`browser.menus` UI (its context menu items are kept but not shown), and frame information for
documents it has no content script on.

### What has been verified, and what has not

- **Verified by running:** everything in `packages/bird_extensions`: `dart test` (170 tests) and
  `dart analyze`, plus 47 shim tests under Node. An integration suite runs the **real shim under
  Node** against the **real Dart host** through a fake transport and a fake browser, covering the
  JSON protocol, permissions, storage, messaging, ports, tabs, webNavigation, toolbar actions,
  menus, alarms, DNS, dynamic content scripts and webRequest verdicts, including hostile input.
- **Verified by static analysis only:** the app wiring (`bird_core/lib/src/extensions`,
  `lib/features/extensions`, the toolbar buttons) and `ladybird/lib/src/extension_bridge.dart`,
  via `flutter analyze`.
- **Not verified at all:** every C++ change. Nothing here compiled the fork or the engine. The new
  C++ was written against signatures read from the tree (and from Ladybird's own
  `TestWindowProxyWorld.cpp`), then re-read, which caught several likely compile errors, but expect
  more on the first build.

## Wire protocol (shim <-> host)

The engine carries opaque strings; the meaning lives in the shim and the Dart host.

- shim -> host: `{"id": 7, "ns": "storage", "method": "get", "args": [...]}`
- host -> shim reply: `{"reply": 7, "result": ...}` or `{"reply": 7, "error": {"message": "..."}}`
- host -> shim event: `{"event": "storage.onChanged", "args": [...]}`
- `runtime.onMessage` carries a `"token"`; the shim answers with the internal call
  `bird.respond(token, {"handled": bool, "value"?, "error"?})`. Only a context the
  message was delivered to may answer it.
- Engine state (`set_extension_state`) is one JSON document:
  `{"shim": "<js>", "extensions": [{"uuid", "id", "init": "<json text>", "contentScripts": [...]}]}`.
  The engine runs `globalThis.__bird_init = <init>;` then the shim in each world, then
  the `document_start` scripts; `document_end`/`document_idle` are requested by the shim
  through `__bird_phase`.

## What the engine changed (fork, all additive)

New files: `LibWeb/HTML/ExtensionHooks.{h,cpp}`, `LibWebView/ExtensionBridge.{h,cpp}`,
`Services/WebContent/ExtensionMatching.{h,cpp}`, `Services/WebContent/ExtensionRuntime.{h,cpp}`.

Existing files touched, each by a few lines: `LibURL/URL.cpp` (a tuple origin for `moz-extension:`),
`LibWebCommon/SecureContexts/AbstractOperations.cpp` (extension origins are trustworthy),
`LibWeb/DOM/Document.cpp` (two hook calls), `LibWeb/Fetch/Fetching/Fetching.cpp` (a `moz-extension`
scheme branch, and the request interception point in `http_network_or_cache_fetch`),
`LibWeb/Loader/ResourceLoader.cpp` (a `moz-extension` branch), `LibWeb/CMakeLists.txt`,
`LibWebView/NavigationLoader.{h,cpp}` (serve an extension page's file for a navigation, as
`file:` is), `LibWebView/{WebContentClient.h,WebContentClient.cpp,Application.cpp,CMakeLists.txt}`,
`Services/WebContent/{WebContentServer,WebContentClient}.ipc` (9 messages),
`Services/WebContent/ConnectionFromClient.{h,cpp}`, `Services/WebContent/CMakeLists.txt`.
In this repo: `packages/libbird/cpp/engine.{h,cpp}` (C API).

How the pieces work:

- **Files.** The WebContent process may not read the profile directory (it is sandboxed), so a
  `moz-extension://<uuid>/path` file is read by the UI process: for a *navigation* in
  `NavigationLoader`, for a *subresource* over `request_extension_resource` / `extension_resource_loaded`.
  `ExtensionBridge::read_resource` confines reads to an extension's own directory (percent-decoding,
  `..` rejected, symlinks resolved).
- **Who may load what.** `Fetching.cpp` asks `ExtensionHooks::allows_extension_resource`: an extension's
  own documents may; web pages only reach `web_accessible_resources`, for the origins the rule names.
- **Extension pages** (background page, popup, options) run in the document's own world with the same
  bridge as content scripts; `browser.tabs` and the rest of the API appear because the shim sees
  `location.protocol === 'moz-extension:'`.
- **Request interception.** A new point in `http_network_or_cache_fetch`, before the existing
  WebDriver BiDi one. It is separate from BiDi because BiDi's machinery is tied to a WebDriver session.
  Only when the state says an extension wants to block (`interceptRequests`), an http(s) request is
  held and described over IPC (`request_extension_intercept`); the UI process hands it to Dart
  (`on_intercept`), Dart asks the extensions' `webRequest` listeners, and the verdict comes back
  (`extension_intercept_verdict`) to cancel, change the URL (a redirect to a `moz-extension:` file works
  because `ResourceLoader` dispatches on the new URL), or set headers. Dart answers within 5 s or the
  request goes ahead.

Design notes worth knowing:

- `PageId` is unique only per WebContent connection; the bridge reports the tab by
  `ViewImplementation::view_id()` and `engine.cpp` maps that to its own view ints.
- A content script's world is `WrapperWorldType::Extension` over the page's `Window`;
  it must be `detach()`ed when its document is destroyed (hooked in `Document::destroy`).
- A WebContent process is only semi-trusted for *which extension* a context belongs to:
  it announces its own contexts. A compromised renderer could claim any extension uuid.
  Mitigation to add: have the UI process mint per-context capabilities. Message answers are already
  restricted to the contexts a message was delivered to.
- The first tab's process is created before extension state exists, so that first page
  load is not injected; the state is pushed to every process as soon as it is set.
- No CSP is applied to extension pages yet.

## Trying it

1. Rebuild the fork (new files, new IPC), then the engine; run `flutter pub get`
   (the new package and dependencies are already in the pubspecs).
2. Open the Extensions popover (puzzle icon, desktop toolbar). Under "Load", enter the
   path of `packages/bird_extensions/example/hello_extension`, or add `ublock-origin` from AMO.
3. `hello_extension`: visit `https://example.com/`. A blue banner appears bottom right, counting
   visits (`browser.storage` through the whole stack).
4. uBlock Origin: its button appears in the toolbar with a badge; the popup is its own page.
   Check the engine's console output for `ExtensionRuntime:` lines, which report scripts that
   failed to parse or threw.
5. Without the app: `dart run bin/bird_ext.dart load example/hello_extension --root /tmp/ext`.

## Architecture

The extension runtime lives in **Dart**; C++ is a thin transport plus the
engine hooks that cannot be done from outside. Tab and window state, bookmarks,
history and the UI are already in Dart, so most API implementations are
natural there, and Dart is statically checkable without building the engine.

```
 extension context (background page, popup, options, content-script world)
   │  browser.* shim (JS, generated from Firefox schemas)
   │  native fn  __bird_ext_call(json) -> Promise
   ▼
 WebContent process ── IPC (ExtensionConnection, modelled on WebUIConnection)
   ▼
 engine.cpp (UI process)  ── NativeCallable.listener ──►  Dart ExtensionHost
   ▲                                                       │ dispatch to API impls
   └────── extensions_respond(request_id, json) ◄──────────┘
           extensions_dispatch_event(target, json)  (events, message delivery)
```

- Calls are JSON-RPC style and asynchronous. Dart answers via
  `extensions_respond`. Events and `runtime.sendMessage` delivery go the other
  way through `extensions_dispatch_event`.
- **Content-script matching must be synchronous in WebContent** (document_start
  cannot wait for a round trip), so Dart pushes a compiled registry (match
  patterns, scripts, CSS, world, run_at) down to every WebContent process.
- **Background page** = a hidden view (no texture) loading
  `moz-extension://<uuid>/<generated page>`. MV3 Firefox uses event pages
  (`background.scripts`), not service workers; ignore `service_worker` when
  `scripts` exists.
- **Origin**: `moz-extension://<uuid>`, uuid random per install (never derived
  from the extension id). Non-special URL schemes get opaque origins by
  default, so the engine needs an explicit rule.
- **Storage layout** under the profile's `extensions/` directory:
  `registry.json`, `installed/<uuid>/` (unpacked files), `storage/<uuid>.json`.

## Engine findings (vendored Ladybird, as of 2026-11-24)

Recorded so they do not have to be rediscovered. Paths are in
`packages/libbird/third_party/ladybird`.

**Already upstream and reusable**

- `Libraries/LibWeb/Bindings/WrapperWorld.h`: `WrapperWorldType::{Main,
  Internal, Extension}`. `Tests/LibWeb/TestWindowProxyWorld.cpp` builds an
  `Extension` realm over a live `Window` using `create_a_new_javascript_realm`,
  `create_global_object_wrapper`, `browsing_context->window_proxy_for(world,
  realm)`, `initialize_window_web_interfaces(window, realm)` and
  `cache_global_object_wrapper`. Non-main worlds must be `detach()`ed before
  being dropped. Nothing in production code creates an Extension world yet.
- `Services/WebContent/WebUIConnection.{h,cpp}` + `WebUIClient/Server.ipc`:
  a per-page IPC channel plus a JS object defined on the realm global
  (`define_direct_property`). The commit that introduced it
  (`41aeb9e63a`) touched 16 existing files (about 75 added lines) and added 9
  new ones; use it as the template for `ExtensionConnection`. Note it is
  per-page and `VERIFY(!m_web_ui)`; extensions need a per-process channel.
- **Network interception framework** (WebDriver BiDi):
  `Libraries/LibWeb/WebDriver/BiDi/Network.{h,cpp}`, call sites in
  `Libraries/LibWeb/Fetch/Fetching/Fetching.cpp` (`get_network_intercepts` /
  `block_network_request` for phases `beforeRequestSent`, `responseStarted`,
  `authRequired`), `NetworkContinuation` actions (Continue,
  ContinueWithModifiedRequest, ProvideResponse, Fail, auth variants), and
  `InterceptionOverrides` (url, method, headers, body, cookie, set-cookie,
  status, reason). Maps almost 1:1 to blocking `webRequest`. Gaps: workers are
  not covered ("reaches only the window agent"); `network_events_enabled()` is
  a cached global flag; `Set-Cookie` is processed in RequestServer
  (`Services/RequestServer/Request.cpp` ~659) before WebContent sees headers.
- `Page::page_did_create_populated_document_with_an_origin_of_its_own`
  (`Libraries/LibWeb/Page/Page.h`, called from `HTML/LocalNavigable.cpp` ~3207)
  is the closest existing document-creation hook; `document_start` needs a new
  PageClient virtual next to it.
- Content blocking: `Libraries/LibWeb/Loader/ContentBlocker.cpp` (adblock-rust),
  consulted in `ResourceLoader::should_block_request`. DNR rules can feed it.

**Network paths that matter for `filterResponseData`**

- Subresources: `Fetching.cpp` ~3136 `ResourceLoader::the().load(...)` with
  `on_headers_received` / `on_data_received`; cached bodies bypass the data
  callback (`on_cached_body_available`) and `TransferLease` hands bodies off
  without passing through WebContent.
- Navigations: fetched in a WebContent process, but the UI process takes the
  body over (`LibWebView/NavigationLoader.cpp`, `set_response_body_callbacks`
  discards body data and `move_response_body_to` re-binds it). A filter on
  navigations must break that hand-off (buffer in the UI process and replay).

**Hot files (commits in 6 months, for merge-conflict planning)**
`LocalNavigable.cpp` 501, `Page.h` 318, `Services/WebContent/PageClient.{h,cpp}`
266/334, `WebContentServer.ipc` 223, `Fetching.cpp` 136, `ResourceLoader.cpp` 51,
`BiDi/Network.cpp` 16, `ContentBlocker.cpp` 8. Keep every existing-file edit a
one-line call into new files; do not append at the tail of lists.

## Package layout (this package, pure Dart)

| File | Role |
|---|---|
| `zip_reader.dart` | Strict ZIP reader: no ZIP64/encryption/duplicates, CRC-checked, inflate-bomb safe |
| `xpi_extractor.dart` | Zip-slip-safe extraction, case-collision and size limits, skips `META-INF/` |
| `manifest.dart` | Firefox-flavoured MV2/MV3 manifest model; lenient like Firefox, warnings not failures |
| `match_pattern.dart` | Match patterns and include/exclude globs |
| `permissions.dart` | Known permissions and Firefox-style prompt text |
| `localization.dart` | `__MSG_x__` resolution, locale choice |
| `amo_client.dart` | AMO API v5 lookup and hash-checked download; https and host allowlist |
| `extension_installer.dart` | Install / update / uninstall with prompt, staging and atomic swap |
| `extension_registry.dart` | `registry.json` with atomic writes and corrupt-file recovery |
| `zip_writer.dart` | Packs a folder into a ZIP so an unpacked extension takes the same install path |
| `engine_state.dart` | Builds the state JSON the web content processes hold (scripts, shim, init) |
| `shim/browser_shim.js` | The `browser`/`chrome` objects of an extension world; embedded via `tool/embed_shim.dart` into `shim_source.dart` |
| `host/extension_host.dart` | Serves API calls, routes events and `runtime.onMessage`, keeps state current |
| `host/storage_api.dart`, `host/runtime_api.dart` | The APIs implemented so far |
| `host/extension_transport.dart` | The channel interface; the app implements it over the engine's C API |
| `bin/bird_ext.dart` | CLI: `info`, `install`, `load`, `update`, `list`, `uninstall` |

## Native messaging

`runtime.connectNative` and `runtime.sendNativeMessage` (extension pages only)
are the `native` namespace of `host/native_messaging_api.dart`. Hosts are found
where Firefox looks for them (`~/Library/Application Support/Mozilla/
NativeMessagingHosts` and the system one on macOS, `~/.mozilla/native-messaging-hosts`
and the system ones on Linux; Windows keeps them in the registry, which is not
read yet). A host manifest must be `type: stdio`, have an absolute `path`, and
list the extension's id in `allowed_extensions`. The program is started with the
manifest's path and the extension id, and speaks JSON after a four byte length in
the machine's byte order, at most 1 MB from the host. A host name that is not
dot-separated words is refused, so it cannot name a path. Tested end to end
against a fake host (`test/native_messaging_test.dart`). Not verified: whether a
real host accepts this browser. 1Password's helper may check which browser started
it and refuse an unknown one.

## Known gaps

- Themes, dictionaries and language packs are rejected (themes are cheap: a
  colour manifest; add with the theme API).
- `optional_permissions` grants and `permissions.request` flow are not built.
- No periodic update check; `ExtensionInstaller.checkForUpdate` exists.
- The permission prompt wording approximates Firefox's; unverified against the
  current strings.
- The list of known permissions may trail Firefox's; unknown ones are kept
  with a warning rather than dropped.

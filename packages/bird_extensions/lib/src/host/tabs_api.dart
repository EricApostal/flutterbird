import 'dart:async';
import 'dart:io';

import '../extension_registry.dart';
import '../manifest.dart';
import '../match_pattern.dart';
import 'api.dart';
import 'browser_bridge.dart';
import 'extension_host.dart';
import 'extension_transport.dart';
import 'runtime_api.dart';

/// `browser.tabs`, over the browser's own tabs.
class TabsApi extends ApiNamespace {
  StreamSubscription<TabEvent>? _subscription;
  ExtensionHost? _host;

  @override
  String get name => 'tabs';

  @override
  void attach(ExtensionHost host) {
    _host = host;
    _subscription = host.browser?.tabEvents.listen(_onTabEvent);
  }

  @override
  void detach() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  /// Whether [extension] may see where [tab] is: with the `tabs` permission,
  /// or access to the host the tab is on.
  static bool canSeeIdentity(InstalledExtension extension, BrowserTab tab) {
    if (extension.grantedPermissions.contains('tabs')) return true;
    final url = Uri.tryParse(tab.url);
    if (url == null) return false;
    return extension.grantedOrigins.any(
      (origin) => MatchPattern.tryParse(origin)?.matches(url) ?? false,
    );
  }

  static Map<String, Object?> present(
    InstalledExtension extension,
    BrowserTab tab,
  ) => tab.toJson(includeIdentity: canSeeIdentity(extension, tab));

  // ------------------------------------------------------------ events

  void _onTabEvent(TabEvent event) {
    final host = _host;
    if (host == null) return;

    switch (event) {
      case TabCreated(:final tab):
        host.emitToAll(
          'tabs.onCreated',
          (extension) => [present(extension, tab)],
        );
      case TabRemoved(:final tabId, :final windowId, :final isWindowClosing):
        host.emitToAll(
          'tabs.onRemoved',
          (_) => [
            tabId,
            {'windowId': windowId, 'isWindowClosing': isWindowClosing},
          ],
        );
      case TabActivated(:final tabId, :final previousTabId, :final windowId):
        host.emitToAll(
          'tabs.onActivated',
          (_) => [
            {
              'tabId': tabId,
              'previousTabId': ?previousTabId,
              'windowId': windowId,
            },
          ],
        );
      case TabUpdated(:final tab, :final changes):
        host.emitToAll('tabs.onUpdated', (extension) {
          final visible = canSeeIdentity(extension, tab);
          final shown = {
            for (final entry in changes.entries)
              if (visible ||
                  !const {'url', 'title', 'favIconUrl'}.contains(entry.key))
                entry.key: entry.value,
          };
          return [tab.id, shown, present(extension, tab)];
        });
    }
  }

  // ------------------------------------------------------------ calls

  @override
  Future<Object?> call(ApiCall call) async {
    final browser = call.host.browser;
    if (browser == null) throw ApiException('Tabs are not available');

    switch (call.method) {
      case 'get':
        return present(call.extension, _requireTab(browser, call.arg(0)));
      case 'getCurrent':
        final viewId = call.context.viewId;
        final tab = viewId == null ? null : browser.tab(viewId);
        return tab == null ? null : present(call.extension, tab);
      case 'query':
        return [
          for (final tab in _query(call, browser, call.arg(0)))
            present(call.extension, tab),
        ];
      case 'create':
        return _create(call, browser);
      case 'update':
        return _update(call, browser);
      case 'remove':
        final ids = call.arg(0);
        for (final id in ids is List ? ids : [ids]) {
          if (id is int) await browser.closeTab(id);
        }
        return null;
      case 'reload':
        final id = _tabIdOrActive(browser, call.arg(0));
        final options = call.arg(1);
        await browser.reloadTab(
          id,
          bypassCache: options is Map && options['bypassCache'] == true,
        );
        return null;
      case 'move':
        return present(call.extension, _requireTab(browser, call.arg(0)));
      case 'getZoom':
        return 1;
      case 'setZoom':
      case 'warmup':
        return null;
      case 'sendMessage':
        return _sendMessage(call, browser);
      case 'connect':
        return _connect(call, browser);
      case 'executeScript':
        return _executeScript(call, browser);
      case 'insertCSS':
        return _insertCss(call, browser);
      case 'removeCSS':
        return null;
      default:
        throw ApiException('tabs.${call.method} is not supported');
    }
  }

  BrowserTab _requireTab(BrowserBridge browser, Object? id) {
    final tab = id is int ? browser.tab(id) : null;
    if (tab == null) throw ApiException('Invalid tab ID: $id');
    return tab;
  }

  int _tabIdOrActive(BrowserBridge browser, Object? id) {
    if (id is int) return _requireTab(browser, id).id;
    final active = browser.activeTabId;
    if (active == null) throw ApiException('There is no active tab');
    return active;
  }

  /// The window `currentWindow` means: the one the asking document is in, or
  /// for a background page or a popup, the one focused last.
  static int currentWindowOf(ApiCall call, BrowserBridge browser) {
    final viewId = call.context.viewId;
    final own = viewId == null ? null : browser.tab(viewId);
    return own?.windowId ?? browser.currentWindowId;
  }

  Iterable<BrowserTab> _query(
    ApiCall call,
    BrowserBridge browser,
    Object? info,
  ) {
    final filter = info is Map ? info : const {};

    bool? flag(String key) => filter[key] is bool ? filter[key] as bool : null;

    final urlFilter = filter['url'];
    final patterns = urlFilter == null
        ? null
        : MatchPatternSet.parse([
            for (final entry in urlFilter is List ? urlFilter : [urlFilter])
              if (entry is String) entry,
          ]);
    final title = filter['title'];
    final titleGlob = title is String ? UrlGlob(title) : null;
    final status = filter['status'];

    final current = currentWindowOf(call, browser);
    final currentWindow = flag('currentWindow');
    final lastFocused = flag('lastFocusedWindow');
    final wantedWindow = filter['windowId'] is int
        // WINDOW_ID_CURRENT.
        ? (filter['windowId'] == -2 ? current : filter['windowId'] as int)
        : null;
    final windowType = filter['windowType'];
    final windowTypes = windowType is String
        ? {for (final window in browser.windows) window.id: window.type}
        : null;

    return browser.tabs.where((tab) {
      if (currentWindow != null && (tab.windowId == current) != currentWindow) {
        return false;
      }
      if (lastFocused != null &&
          (tab.windowId == browser.currentWindowId) != lastFocused) {
        return false;
      }
      if (windowTypes != null && windowTypes[tab.windowId] != windowType) {
        return false;
      }
      if (flag('active') != null && tab.active != flag('active')) return false;
      if (flag('highlighted') != null && tab.active != flag('highlighted')) {
        return false;
      }
      if (flag('pinned') == true ||
          flag('audible') == true ||
          flag('discarded') == true) {
        return false;
      }
      if (wantedWindow != null && wantedWindow != tab.windowId) {
        return false;
      }
      if (filter['index'] is int && filter['index'] != tab.index) return false;
      if (status is String &&
          status != (tab.isLoading ? 'loading' : 'complete')) {
        return false;
      }
      if (patterns != null && !patterns.matchesString(tab.url)) return false;
      if (titleGlob != null && !titleGlob.matches(tab.title)) return false;
      return true;
    });
  }

  Future<Object?> _create(ApiCall call, BrowserBridge browser) async {
    final properties = call.arg(0);
    final map = properties is Map ? properties : const {};
    final url = map['url'];
    final windowId = map['windowId'];
    final tab = await browser.createTab(
      url: url is String ? url : null,
      active: map['active'] is bool ? map['active']! as bool : true,
      windowId: windowId is int && windowId >= 0 ? windowId : null,
    );
    return present(call.extension, tab);
  }

  Future<Object?> _update(ApiCall call, BrowserBridge browser) async {
    // update([tabId], properties): the tab is optional and defaults to the active one.
    final first = call.arg(0);
    final id = first is int ? first : null;
    final properties = id == null ? first : call.arg(1);
    final map = properties is Map ? properties : const {};

    final tabId = _tabIdOrActive(browser, id);
    final url = map['url'];
    await browser.updateTab(
      tabId,
      url: url is String ? url : null,
      active: map['active'] is bool ? map['active'] as bool : null,
    );
    final tab = browser.tab(tabId);
    return tab == null ? null : present(call.extension, tab);
  }

  // ------------------------------------------------------------ talking to a tab

  /// The contexts of this extension in [tabId]'s documents, narrowed by
  /// `frameId` when one is given.
  Iterable<ExtensionContext> _contextsInTab(
    ApiCall call,
    int tabId,
    Object? frameId,
  ) {
    return call.host.contextsOf(call.extension.uuid).where((context) {
      if (context.kind != ExtensionContextKind.contentScript ||
          context.viewId != tabId) {
        return false;
      }
      if (frameId is int) return call.host.frameIdOf(context) == frameId;
      return true;
    });
  }

  Future<Object?> _sendMessage(ApiCall call, BrowserBridge browser) {
    final tabId = _requireTab(browser, call.arg(0)).id;
    final options = call.arg(2);
    final frameId = options is Map ? options['frameId'] : null;

    final targets = _contextsInTab(call, tabId, frameId)
        .where(
          (context) => call.host.events.isListening(
            context.contextId,
            'runtime.onMessage',
          ),
        )
        .toList();
    if (targets.isEmpty) {
      throw ApiException(
        'Could not establish connection. Receiving end does not exist.',
      );
    }
    return call.host.deliverMessage(
      targets,
      call.arg(1),
      RuntimeApi.senderFor(call.host, call),
    );
  }

  Object? _connect(ApiCall call, BrowserBridge browser) {
    final portId = call.arg(0);
    final tabId = _requireTab(browser, call.arg(1)).id;
    final portName = call.arg(2);
    if (portId is! String) throw ApiException('tabs.connect needs a port id');

    final targets = _contextsInTab(call, tabId, call.arg(3))
        .where(
          (context) => call.host.events.isListening(
            context.contextId,
            'runtime.onConnect',
          ),
        )
        .toList();
    if (targets.isEmpty) {
      throw ApiException(
        'Could not establish connection. Receiving end does not exist.',
      );
    }

    call.host.openPort(
      portId: portId,
      name: portName is String ? portName : '',
      opener: call.context,
      targets: targets,
      sender: RuntimeApi.senderFor(call.host, call),
    );
    return null;
  }

  Future<String> _scriptSource(
    ApiCall call,
    Object? details, {
    required String kind,
  }) async {
    final map = details is Map ? details : const {};
    final code = map['code'];
    if (code is String) return code;

    final file = map['file'];
    if (file is String) {
      final path = normalizeResourcePath(file);
      if (path == null) throw ApiException('Invalid file "$file"');
      final target = File(
        '${call.host.registry.directoryFor(call.extension).path}/$path',
      );
      try {
        return await target.readAsString();
      } on FileSystemException {
        throw ApiException('Could not read "$file"');
      }
    }
    throw ApiException('tabs.$kind needs "code" or "file"');
  }

  Iterable<ExtensionContext> _scriptTargets(
    ApiCall call,
    BrowserBridge browser,
    int tabId,
    Map<Object?, Object?> details,
  ) {
    final frameId = details['frameId'];
    final all = details['allFrames'] == true;
    return _contextsInTab(
      call,
      tabId,
      frameId,
    ).where((context) => frameId is int || all || context.isTopLevel);
  }

  Future<Object?> _executeScript(ApiCall call, BrowserBridge browser) async {
    // executeScript([tabId], details)
    final first = call.arg(0);
    final id = first is int ? first : null;
    final details = id == null ? first : call.arg(1);
    final map = details is Map ? details : const {};
    final tabId = _tabIdOrActive(browser, id);

    final code = await _scriptSource(call, map, kind: 'executeScript');
    final targets = _scriptTargets(call, browser, tabId, map).toList();
    if (targets.isEmpty) return const <Object?>[];
    return call.host.askContexts(targets, 'bird.eval', [code]);
  }

  Future<Object?> _insertCss(ApiCall call, BrowserBridge browser) async {
    final first = call.arg(0);
    final id = first is int ? first : null;
    final details = id == null ? first : call.arg(1);
    final map = details is Map ? details : const {};
    final tabId = _tabIdOrActive(browser, id);

    final css = await _scriptSource(call, map, kind: 'insertCSS');
    for (final target in _scriptTargets(call, browser, tabId, map)) {
      call.host.dispatchEvent(target.contextId, 'bird.insertCss', [css]);
    }
    return null;
  }
}

// ---------------------------------------------------------------- scripting

/// `browser.scripting`: running an extension's scripts and stylesheets in the
/// documents of a tab, in the world its content scripts run in.
class ScriptingApi extends ApiNamespace {
  @override
  String get name => 'scripting';

  @override
  String? get requiredPermission => 'scripting';

  @override
  Future<Object?> call(ApiCall call) async {
    final injection = call.arg(0);
    final target = injection is Map ? injection['target'] : null;
    if (injection is! Map || target is! Map || target['tabId'] is! int) {
      throw ApiException('scripting.${call.method} needs a target tab');
    }
    if (injection['world'] == 'MAIN') {
      throw ApiException('Running in the main world is not supported yet');
    }

    final targets = _targets(call, target).toList();

    switch (call.method) {
      case 'executeScript':
        final code = await _source(call, injection, 'code');
        // One answer per document, so that each result names its frame.
        return Future.wait([
          for (final context in targets)
            call.host
                .askContexts([context], 'bird.eval', [code])
                .then(
                  (values) => <String, Object?>{
                    'frameId': call.host.frameIdOf(context),
                    'result': values.isNotEmpty ? values.first : null,
                  },
                  onError: (Object error) => <String, Object?>{
                    'frameId': call.host.frameIdOf(context),
                    'error': {'message': '$error'},
                  },
                ),
        ]);
      case 'insertCSS':
        final css = await _source(call, injection, 'css');
        for (final context in targets) {
          call.host.dispatchEvent(context.contextId, 'bird.insertCss', [css]);
        }
        return null;
      default:
        throw ApiException('scripting.${call.method} is not supported');
    }
  }

  Iterable<ExtensionContext> _targets(
    ApiCall call,
    Map<Object?, Object?> target,
  ) {
    final frames = target['frameIds'];
    final all = target['allFrames'] == true;
    return call.host.contextsOf(call.extension.uuid).where((context) {
      if (context.kind != ExtensionContextKind.contentScript ||
          context.viewId != target['tabId']) {
        return false;
      }
      if (frames is List) return frames.contains(call.host.frameIdOf(context));
      return all || context.isTopLevel;
    });
  }

  /// The text under [inline], or that of the extension's `files`, in order.
  Future<String> _source(
    ApiCall call,
    Map<Object?, Object?> injection,
    String inline,
  ) async {
    final text = injection[inline];
    if (text is String) return text;

    final files = injection['files'];
    if (files is! List || files.isEmpty) {
      throw ApiException('scripting.${call.method} needs "files"');
    }
    final parts = <String>[];
    for (final file in files) {
      final path = file is String ? normalizeResourcePath(file) : null;
      if (path == null) throw ApiException('Invalid file "$file"');
      try {
        parts.add(
          await File(
            '${call.host.registry.directoryFor(call.extension).path}/$path',
          ).readAsString(),
        );
      } on FileSystemException {
        throw ApiException('Could not read "$file"');
      }
    }
    return parts.join(inline == 'css' ? '\n' : '\n;\n');
  }
}

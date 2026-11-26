import 'dart:async';

import 'package:flutter/widgets.dart';

import '../model/session.dart';
import '../model/settings.dart';
import '../protocol/devtools_connection.dart';

/// What the browser the tools are part of has to provide.
abstract class DevToolsHost {
  /// Starts the engine's DevTools server if it is not running, and returns the
  /// port it listens on. The server runs only while tools are open: it lets
  /// whoever connects run script in any tab.
  Future<int> startServer();

  void stopServer();

  /// The number the DevTools server knows a tab by, or null if it has none.
  int? browserIdFor(int tabId);

  void openLink(String url, {required int fromTab});

  /// Saves [bytes] where the user will find them. Returns where, if known.
  Future<String?> saveFile(String suggestedName, List<int> bytes);
}

/// The developer tools of one tab, as the browser sees them.
class TabDevTools {
  TabDevTools(this.tabId, this.panel);

  final int tabId;

  /// The tool showing.
  String panel;

  /// Null until there is a connection to make it with.
  ToolboxSession? session;
  String error = '';
  bool responsive = false;

  /// Whether the toolbox itself is open: Responsive Design Mode can be on
  /// without it.
  bool toolboxOpen = true;

  final FocusScopeNode focus = FocusScopeNode(debugLabel: 'devtools');
  bool _closed = false;
}

/// Opens and closes developer tools for tabs. The engine's server takes one
/// client, so every tab's tools share a connection.
class DevToolsManager extends ChangeNotifier {
  DevToolsManager(this.host, {DevToolsSettings? settings, Future<DevToolsConnection> Function(int port)? connect})
    : settings = settings ?? DevToolsSettings(),
      _connect = connect ?? DevToolsConnection.open;

  final DevToolsHost host;
  final DevToolsSettings settings;
  final Future<DevToolsConnection> Function(int port) _connect;

  final Map<int, TabDevTools> _tabs = {};
  Future<DevToolsConnection>? _connection;
  Future<void> _closing = Future.value();

  /// Whether the browser can put a toolbox in a window of its own.
  bool supportsSeparateWindow = false;

  /// Told when a tab's tools open or close in a window of their own.
  void Function(int tabId, bool open)? onWindowedChanged;

  TabDevTools? stateOf(int tabId) => _tabs[tabId];

  bool isOpen(int tabId) => _tabs[tabId]?.toolboxOpen ?? false;

  DevToolsDock get dock {
    final dock = settings.dock;
    return dock == DevToolsDock.window && !supportsSeparateWindow ? DevToolsDock.bottom : dock;
  }

  void setDock(DevToolsDock dock) {
    settings.dock = dock;
    for (final tab in _tabs.values) {
      onWindowedChanged?.call(tab.tabId, tab.toolboxOpen && dock == DevToolsDock.window);
    }
    notifyListeners();
  }

  Future<DevToolsConnection> _ensureConnection() {
    return _connection ??= () async {
      await _closing;
      final port = await host.startServer();
      Object? failure;
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          final connection = await _connect(port);
          unawaited(connection.done.then((_) => _connection = null));
          return connection;
        } catch (error) {
          failure = error;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      throw failure!;
    }();
  }

  /// Opens the tools of a tab, on [panel] if one is named.
  Future<ToolboxSession?> open(int tabId, {String? panel}) async {
    var tab = _tabs[tabId];
    if (tab != null) {
      final wasClosed = !tab.toolboxOpen;
      tab.toolboxOpen = true;
      if (panel != null) selectPanel(tabId, panel);
      if (wasClosed) {
        if (dock == DevToolsDock.window) onWindowedChanged?.call(tabId, true);
        notifyListeners();
      }
    } else {
      tab = _tabs[tabId] = TabDevTools(tabId, panel ?? settings.panel);
      if (panel != null) settings.panel = panel;
      if (dock == DevToolsDock.window) onWindowedChanged?.call(tabId, true);
      notifyListeners();
    }
    return _attach(tab);
  }

  final Map<TabDevTools, Future<ToolboxSession?>> _attaching = {};

  Future<ToolboxSession?> _attach(TabDevTools tab) {
    final session = tab.session;
    if (session != null) return Future.value(session);
    return _attaching[tab] ??= _createSession(tab).whenComplete(() {
      _attaching.remove(tab);
    });
  }

  Future<ToolboxSession?> _createSession(TabDevTools tab) async {
    tab.error = '';
    try {
      final connection = await _ensureConnection();
      if (tab._closed) return null;
      final browserId = host.browserIdFor(tab.tabId);
      if (browserId == null) throw StateError('The engine does not know this tab.');
      final session = ToolboxSession(connection: connection, browserId: browserId, settings: settings)
        ..onSelectTool = ((panel) => selectPanel(tab.tabId, panel))
        ..onOpenLink = ((url) => host.openLink(url, fromTab: tab.tabId))
        ..onSaveFile = ((name, bytes) async {
          final path = await host.saveFile(name, bytes);
          if (path != null) tab.session?.console.addNotice('Saved to $path');
        });
      tab.session = session;
      notifyListeners();
      await session.start();
      return session;
    } catch (error) {
      if (tab._closed) return null;
      debugPrint('DevTools could not open: $error');
      tab.error = '$error';
      _connection = null;
      notifyListeners();
      return null;
    }
  }

  void retry(int tabId) {
    final tab = _tabs[tabId];
    if (tab == null) return;
    tab.session?.dispose();
    tab.session = null;
    tab.error = '';
    notifyListeners();
    _attach(tab);
  }

  void selectPanel(int tabId, String panel) {
    final tab = _tabs[tabId];
    if (tab == null || tab.panel == panel) return;
    tab.panel = panel;
    if (panel != 'settings') settings.panel = panel;
    notifyListeners();
  }

  /// Closes the toolbox, as the shortcut that opened it does.
  void toggle(int tabId) => isOpen(tabId) ? close(tabId) : open(tabId);

  /// A tool's own shortcut: shows it, or closes the toolbox if it is already
  /// what has the keyboard.
  void toggleTool(int tabId, String panel) {
    final tab = _tabs[tabId];
    if (tab != null && tab.toolboxOpen && tab.panel == panel && tab.focus.hasFocus) {
      close(tabId);
    } else {
      open(tabId, panel: panel);
    }
  }

  Future<void> togglePicker(int tabId) async {
    final existing = _tabs[tabId]?.session;
    if (existing != null && isOpen(tabId)) {
      existing.inspector.togglePicker();
      return;
    }
    final session = await open(tabId, panel: 'inspector');
    if (session == null) return;
    // The walker follows the session by a moment.
    for (var i = 0; i < 40 && session.inspector.root == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 75));
    }
    await session.inspector.startPicker();
  }

  /// "Inspect" in the page's menu: opens the Inspector, and then has [select]
  /// point the engine at the element.
  Future<void> inspectElement(int tabId, void Function() select) async {
    final session = await open(tabId, panel: 'inspector');
    if (session == null) return;
    for (var i = 0; i < 60 && session.inspector.selected == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 75));
    }
    select();
  }

  void toggleResponsive(int tabId) {
    final tab = _tabs[tabId] ??= TabDevTools(tabId, settings.panel)..toolboxOpen = false;
    tab.responsive = !tab.responsive;
    if (!tab.responsive && !tab.toolboxOpen) _remove(tabId);
    notifyListeners();
  }

  void close(int tabId) {
    final tab = _tabs[tabId];
    if (tab == null) return;
    if (dock == DevToolsDock.window) onWindowedChanged?.call(tabId, false);
    // Responsive Design Mode stays on without the toolbox.
    if (tab.responsive) {
      tab.toolboxOpen = false;
      _release(tab);
    } else {
      _remove(tabId);
    }
    notifyListeners();
    _closeConnectionIfIdle();
  }

  /// The tab itself is gone.
  void tabClosed(int tabId) {
    if (!_tabs.containsKey(tabId)) return;
    if (dock == DevToolsDock.window) onWindowedChanged?.call(tabId, false);
    _remove(tabId);
    notifyListeners();
    _closeConnectionIfIdle();
  }

  void _release(TabDevTools tab) {
    final session = tab.session;
    tab.session = null;
    session?.dispose();
  }

  void _remove(int tabId) {
    final tab = _tabs.remove(tabId);
    if (tab == null) return;
    tab._closed = true;
    _release(tab);
    // The widgets showing the toolbox let go of the node in the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.focus.dispose());
  }

  void _closeConnectionIfIdle() {
    if (_tabs.values.any((tab) => tab.toolboxOpen || tab.session != null)) return;
    final pending = _connection;
    if (pending == null) {
      return;
    }
    _connection = null;
    _closing = () async {
      try {
        final connection = await pending;
        // An answer means the server has read what was sent before the
        // goodbye: the resume of a paused page among it.
        await connection
            .request('root', 'getRoot', const {}, const Duration(seconds: 1))
            .then<void>((_) {}, onError: (Object _) {});
        await connection.close();
      } catch (_) {
        // It never opened.
      }
      host.stopServer();
    }();
  }

  /// Closes everything, as the app quits.
  void shutDown() {
    for (final id in _tabs.keys.toList()) {
      _remove(id);
    }
    _closeConnectionIfIdle();
    settings.flush();
  }
}

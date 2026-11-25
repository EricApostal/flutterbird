import 'dart:async';

import '../extension_registry.dart';

/// A browser tab as extensions see it. [id] is the app's own view id, which
/// is also what an extension context reports as the tab it is in.
class BrowserTab {
  const BrowserTab({
    required this.id,
    required this.index,
    required this.active,
    required this.url,
    required this.title,
    required this.isLoading,
    this.favIconUrl,
    this.windowId = 1,
  });

  final int id;
  final int index;
  final bool active;
  final String url;
  final String title;
  final bool isLoading;
  final String? favIconUrl;
  final int windowId;

  /// The `tabs.Tab` object. [includeIdentity] is false for an extension that
  /// has no permission to see where the tab is: it then gets no url, title or
  /// icon.
  Map<String, Object?> toJson({required bool includeIdentity}) => {
    'id': id,
    'index': index,
    'windowId': windowId,
    'active': active,
    'highlighted': active,
    'pinned': false,
    'audible': false,
    'discarded': false,
    'incognito': false,
    'status': isLoading ? 'loading' : 'complete',
    if (includeIdentity) ...{
      'url': url,
      'title': title,
      'favIconUrl': ?favIconUrl,
    },
  };
}

/// A browser window as extensions see it.
class BrowserWindowInfo {
  const BrowserWindowInfo({
    required this.id,
    this.type = 'normal',
    this.focused = false,
    this.state = 'normal',
    this.left = 0,
    this.top = 0,
    this.width = 1280,
    this.height = 800,
  });

  final int id;

  /// `normal`, or `popup` for a window with no tab strip.
  final String type;
  final bool focused;

  /// `normal` or `fullscreen`.
  final String state;
  final int left;
  final int top;
  final int width;
  final int height;

  /// The `windows.Window` object, without its tabs.
  Map<String, Object?> toJson() => {
    'id': id,
    'focused': focused,
    'incognito': false,
    'alwaysOnTop': false,
    'type': type,
    'state': state,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}

sealed class WindowEvent {
  const WindowEvent();
}

class WindowCreated extends WindowEvent {
  const WindowCreated(this.window);

  final BrowserWindowInfo window;
}

class WindowRemoved extends WindowEvent {
  const WindowRemoved(this.windowId);

  final int windowId;
}

class WindowFocusChanged extends WindowEvent {
  const WindowFocusChanged(this.windowId);

  final int windowId;
}

sealed class TabEvent {
  const TabEvent();
}

class TabCreated extends TabEvent {
  const TabCreated(this.tab);

  final BrowserTab tab;
}

/// Something about a tab changed; [changes] names it the way `changeInfo`
/// does (`url`, `title`, `status`, `favIconUrl`).
class TabUpdated extends TabEvent {
  const TabUpdated(this.tab, this.changes);

  final BrowserTab tab;
  final Map<String, Object?> changes;
}

class TabRemoved extends TabEvent {
  const TabRemoved(
    this.tabId, {
    this.windowId = 1,
    this.isWindowClosing = false,
  });

  final int tabId;
  final int windowId;

  /// Whether the tab went because its window did.
  final bool isWindowClosing;
}

class TabActivated extends TabEvent {
  const TabActivated(this.tabId, this.previousTabId, {this.windowId = 1});

  final int tabId;
  final int? previousTabId;
  final int windowId;
}

/// What the host needs from the browser: its tabs and windows, and a place to
/// run an extension's background page. The app implements it.
abstract class BrowserBridge {
  List<BrowserTab> get tabs;

  BrowserTab? tab(int id) {
    for (final candidate in tabs) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  /// The active tab of the current window.
  int? get activeTabId;

  Stream<TabEvent> get tabEvents;

  /// A browser that does not say otherwise has one window.
  List<BrowserWindowInfo> get windows => const [
    BrowserWindowInfo(id: 1, focused: true),
  ];

  /// The window focused last.
  int get currentWindowId => 1;

  Stream<WindowEvent> get windowEvents => const Stream.empty();

  /// Opens a window on [url] and returns its id. A browser with one window
  /// opens a tab in it instead.
  Future<int> createWindow({
    String? url,
    bool popup = false,
    int? width,
    int? height,
  }) async => (await createTab(url: url)).windowId;

  Future<void> focusWindow(int id) async {}

  Future<void> closeWindow(int id) async {}

  /// Opens a tab in [windowId], or in the current window.
  Future<BrowserTab> createTab({
    String? url,
    bool active = true,
    int? windowId,
  });

  Future<void> updateTab(int id, {String? url, bool? active});

  Future<void> closeTab(int id);

  Future<void> reloadTab(int id, {bool bypassCache = false});

  /// Starts [extension]'s background page at [url], which is
  /// `moz-extension://<uuid>/<page>`. It has no window. The browser reports
  /// the page's context through the transport once it loads.
  Future<void> startBackgroundPage(InstalledExtension extension, String url);

  Future<void> stopBackgroundPage(InstalledExtension extension);
}

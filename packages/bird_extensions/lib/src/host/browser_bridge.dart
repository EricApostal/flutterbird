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
  const TabRemoved(this.tabId);

  final int tabId;
}

class TabActivated extends TabEvent {
  const TabActivated(this.tabId, this.previousTabId);

  final int tabId;
  final int? previousTabId;
}

/// What the host needs from the browser: its tabs, and a place to run an
/// extension's background page. The app implements it.
abstract class BrowserBridge {
  List<BrowserTab> get tabs;

  BrowserTab? tab(int id) {
    for (final candidate in tabs) {
      if (candidate.id == id) return candidate;
    }
    return null;
  }

  int? get activeTabId;

  Stream<TabEvent> get tabEvents;

  Future<BrowserTab> createTab({String? url, bool active = true});

  Future<void> updateTab(int id, {String? url, bool? active});

  Future<void> closeTab(int id);

  Future<void> reloadTab(int id, {bool bypassCache = false});

  /// Starts [extension]'s background page at [url], which is
  /// `moz-extension://<uuid>/<page>`. It has no window. The browser reports
  /// the page's context through the transport once it loads.
  Future<void> startBackgroundPage(InstalledExtension extension, String url);

  Future<void> stopBackgroundPage(InstalledExtension extension);
}

/// Which window each tab is in.
///
/// A tab is named by the id of its web view. Every operation returns a new
/// session and keeps these true:
///
///  * a tab is in one window at most,
///  * a window with tabs has one of them active,
///  * a window left with no tabs is removed, unless it is held.
///
/// No window is special. Closing one closes its tabs and nothing else, and the
/// app has nothing left to do only when no window is left.
library;

enum BrowserWindowKind {
  /// A browser window, with a tab strip that tabs can be dragged to and from.
  normal,

  /// A window a page opened as a popup, such as to sign in: one page, no tab
  /// strip.
  popup,
}

final class BrowserWindowModel {
  const BrowserWindowModel({
    required this.id,
    required this.kind,
    this.tabIds = const [],
    this.activeTabId,
    this.isHeld = false,
  });

  final int id;
  final BrowserWindowKind kind;

  /// In the order the tab strip shows them.
  final List<int> tabIds;

  /// Null only in a held window with no tabs.
  final int? activeTabId;

  /// Whether the window outlives having no tabs, as the window a tab is being
  /// dragged out of does until the drag is over.
  final bool isHeld;

  bool get isPopup => kind == BrowserWindowKind.popup;

  BrowserWindowModel _with({
    List<int>? tabIds,
    int? Function()? activeTabId,
    bool? isHeld,
  }) => BrowserWindowModel(
    id: id,
    kind: kind,
    tabIds: tabIds == null ? this.tabIds : List.unmodifiable(tabIds),
    activeTabId: activeTabId == null ? this.activeTabId : activeTabId(),
    isHeld: isHeld ?? this.isHeld,
  );

  @override
  bool operator ==(Object other) =>
      other is BrowserWindowModel &&
      other.id == id &&
      other.kind == kind &&
      other.activeTabId == activeTabId &&
      other.isHeld == isHeld &&
      _sameList(other.tabIds, tabIds);

  @override
  int get hashCode =>
      Object.hash(id, kind, activeTabId, isHeld, Object.hashAll(tabIds));

  @override
  String toString() =>
      'BrowserWindowModel($id, ${kind.name}, tabs: $tabIds, '
      'active: $activeTabId${isHeld ? ', held' : ''})';
}

bool _sameList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final class BrowserSession {
  const BrowserSession._(this.windows, this.focusOrder, this.nextWindowId);

  static const BrowserSession empty = BrowserSession._([], [], 1);

  /// A session of one window holding [tabIds].
  factory BrowserSession.single(List<int> tabIds) =>
      empty.openWindow(tabIds: tabIds).session;

  /// In the order they were opened.
  final List<BrowserWindowModel> windows;

  /// The windows' ids, the one focused last first.
  final List<int> focusOrder;

  /// Ids are never reused, so that nothing mistakes a new window for one that
  /// was closed.
  final int nextWindowId;

  bool get isEmpty => windows.isEmpty;

  int? get focusedWindowId => focusOrder.isEmpty ? null : focusOrder.first;

  BrowserWindowModel? window(int id) {
    for (final window in windows) {
      if (window.id == id) return window;
    }
    return null;
  }

  BrowserWindowModel? windowOfTab(int tabId) {
    for (final window in windows) {
      if (window.tabIds.contains(tabId)) return window;
    }
    return null;
  }

  /// The window of [kind] that was focused last and has tabs.
  BrowserWindowModel? lastFocused({BrowserWindowKind? kind}) {
    for (final id in focusOrder) {
      final candidate = window(id);
      if (candidate == null || candidate.tabIds.isEmpty) continue;
      if (kind == null || candidate.kind == kind) return candidate;
    }
    return null;
  }

  /// The active tab of the window focused last.
  int? get focusedTabId => lastFocused()?.activeTabId;

  Iterable<int> get allTabIds sync* {
    for (final window in windows) {
      yield* window.tabIds;
    }
  }

  /// Opens a window. Any of [tabIds] that is in a window already moves.
  ({BrowserSession session, int windowId}) openWindow({
    BrowserWindowKind kind = BrowserWindowKind.normal,
    List<int> tabIds = const [],
    int? activeTabId,
    bool focus = true,
  }) {
    var base = this;
    for (final tabId in tabIds) {
      base = base.removeTab(tabId);
    }

    final id = base.nextWindowId;
    final opened = BrowserWindowModel(
      id: id,
      kind: kind,
      tabIds: List.unmodifiable(tabIds),
      activeTabId: tabIds.isEmpty
          ? null
          : (activeTabId != null && tabIds.contains(activeTabId)
                ? activeTabId
                : tabIds.first),
    );

    return (
      session: BrowserSession._(
        List.unmodifiable([...base.windows, opened]),
        List.unmodifiable(
          focus ? [id, ...base.focusOrder] : [...base.focusOrder, id],
        ),
        id + 1,
      ),
      windowId: id,
    );
  }

  /// Puts a tab that is in no window into [windowId], at [index] or the end.
  BrowserSession insertTab(
    int windowId,
    int tabId, {
    int? index,
    bool activate = true,
  }) {
    final target = window(windowId);
    if (target == null || windowOfTab(tabId) != null) return this;

    final tabs = [...target.tabIds];
    tabs.insert((index ?? tabs.length).clamp(0, tabs.length), tabId);
    return _replace(
      target._with(
        tabIds: tabs,
        activeTabId: () => activate ? tabId : (target.activeTabId ?? tabId),
      ),
    );
  }

  /// Takes a tab out of its window. If it was the one showing, its neighbour
  /// is shown instead: the one before it, or after it for the first.
  BrowserSession removeTab(int tabId) {
    final source = windowOfTab(tabId);
    if (source == null) return this;

    final index = source.tabIds.indexOf(tabId);
    final tabs = [...source.tabIds]..removeAt(index);
    if (tabs.isEmpty && !source.isHeld) return _drop(source.id);

    return _replace(
      source._with(
        tabIds: tabs,
        activeTabId: () => source.activeTabId != tabId
            ? source.activeTabId
            : (tabs.isEmpty ? null : tabs[index == 0 ? 0 : index - 1]),
      ),
    );
  }

  /// Closes a window along with whatever tabs it has. The caller disposes of
  /// them: ask [window] for them first.
  BrowserSession closeWindow(int windowId) =>
      window(windowId) == null ? this : _drop(windowId);

  /// Moves a tab to [index] of [toWindowId], which may be the window it is in.
  /// [index] counts the target's tabs without the one that is moving.
  BrowserSession moveTab(
    int tabId,
    int toWindowId, {
    int? index,
    bool activate = true,
  }) {
    final source = windowOfTab(tabId);
    final target = window(toWindowId);
    if (source == null || target == null) return this;

    if (source.id == target.id) {
      final tabs = [...source.tabIds]..remove(tabId);
      tabs.insert((index ?? tabs.length).clamp(0, tabs.length), tabId);
      return _replace(
        source._with(
          tabIds: tabs,
          activeTabId: () => activate ? tabId : source.activeTabId,
        ),
      );
    }

    return removeTab(
      tabId,
    ).insertTab(toWindowId, tabId, index: index, activate: activate);
  }

  /// Moves the tab at [from] to [to] within its window.
  BrowserSession reorderTab(int windowId, int from, int to) {
    final target = window(windowId);
    if (target == null || from < 0 || from >= target.tabIds.length) {
      return this;
    }
    final tabs = [...target.tabIds];
    final tab = tabs.removeAt(from);
    tabs.insert(to.clamp(0, tabs.length), tab);
    return _replace(target._with(tabIds: tabs));
  }

  /// Moves a tab into a new window of its own.
  ({BrowserSession session, int windowId}) detachTab(
    int tabId, {
    bool focus = true,
  }) => openWindow(tabIds: [tabId], focus: focus);

  /// Shows a tab in its window. Which window is focused is left alone.
  BrowserSession activateTab(int tabId) {
    final target = windowOfTab(tabId);
    if (target == null || target.activeTabId == tabId) return this;
    return _replace(target._with(activeTabId: () => tabId));
  }

  BrowserSession focusWindow(int windowId) {
    if (window(windowId) == null || focusedWindowId == windowId) return this;
    return BrowserSession._(
      windows,
      List.unmodifiable([
        windowId,
        ...focusOrder.where((id) => id != windowId),
      ]),
      nextWindowId,
    );
  }

  /// Keeps a window around even with no tabs, until [releaseWindow].
  BrowserSession holdWindow(int windowId) {
    final target = window(windowId);
    if (target == null || target.isHeld) return this;
    return _replace(target._with(isHeld: true));
  }

  /// Ends a hold, closing the window if it has no tabs.
  BrowserSession releaseWindow(int windowId) {
    final target = window(windowId);
    if (target == null || !target.isHeld) return this;
    if (target.tabIds.isEmpty) return _drop(windowId);
    return _replace(target._with(isHeld: false));
  }

  BrowserSession _replace(BrowserWindowModel changed) {
    final previous = window(changed.id);
    if (previous == changed) return this;
    return BrowserSession._(
      List.unmodifiable([
        for (final window in windows)
          if (window.id == changed.id) changed else window,
      ]),
      focusOrder,
      nextWindowId,
    );
  }

  BrowserSession _drop(int windowId) => BrowserSession._(
    List.unmodifiable(windows.where((window) => window.id != windowId)),
    List.unmodifiable(focusOrder.where((id) => id != windowId)),
    nextWindowId,
  );

  @override
  String toString() => 'BrowserSession(focus: $focusOrder, $windows)';
}

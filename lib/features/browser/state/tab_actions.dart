import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/state/history_bitmap_cache.dart';
import 'package:flutterbird/features/browser/state/tab_preview_cache.dart';
import 'package:go_router/go_router.dart';
import 'package:ladybird/ladybird.dart';

// A tab that was closed, as much of it as can be brought back: where it was.
class ClosedTabRecord {
  const ClosedTabRecord({required this.url, required this.title});

  final String url;
  final String title;
}

// The tabs that are on their way out: the close was accepted and their row is
// collapsing, but they are still in the tab list. Every close path goes through
// [BrowserTabActions.closeTab], so the strip and the sidebar animate a close
// the same however it started (the tab's own button, Cmd+W, the menu).
class ClosingTabsNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => const <int>{};

  void begin(int viewId) => state = {...state, viewId};

  void finish(int viewId) {
    if (!state.contains(viewId)) return;
    state = {...state}..remove(viewId);
  }
}

final closingTabsProvider = NotifierProvider<ClosingTabsNotifier, Set<int>>(
  ClosingTabsNotifier.new,
);

class BrowserTabActions {
  static LadybirdController openNewTab(WidgetRef ref, BuildContext context) {
    final controller = ref.read(browserTabControllerProvider.notifier).add();
    context.go('/browser/tab/${controller.viewId}');
    return controller;
  }

  // The tab that opened each tab that a page opened (a link that opens a new
  // tab, window.open, view source), by view id. Going back from the start of such
  // a tab closes it and returns to the one that opened it, as in a browser. A tab
  // the user opened themselves has no opener, and going back from it leaves the
  // app.
  static final Map<int, int> _openerByTab = <int, int>{};

  // The tab that opened [viewId], if both still exist.
  static int? openerOf(WidgetRef ref, int viewId) {
    final opener = _openerByTab[viewId];
    if (opener == null) return null;
    final exists = ref
        .read(browserTabControllerProvider)
        .any((tab) => tab.viewId == opener);
    return exists ? opener : null;
  }

  static LadybirdController openExistingTab(
    WidgetRef ref,
    BuildContext context,
    int existingViewId, {
    bool activate = true,
    int? openerViewId,
  }) {
    if (openerViewId != null && openerViewId != existingViewId) {
      _openerByTab[existingViewId] = openerViewId;
    }
    final controller = ref
        .read(browserTabControllerProvider.notifier)
        .addExisting(existingViewId);
    if (activate) {
      context.go('/browser/tab/${controller.viewId}');
    }
    return controller;
  }

  static bool prepareCloseTabNavigation(
    BuildContext context, {
    required int currentViewId,
    required int closeViewId,
    required List<LadybirdController> tabs,
    int? destinationViewId,
  }) {
    final index = tabs.indexWhere((tab) => tab.viewId == closeViewId);
    if (index < 0) return false;

    if (closeViewId == currentViewId) {
      if (tabs.length == 1) {
        exit(0);
      }

      final preferredIndex = destinationViewId == null
          ? -1
          : tabs.indexWhere((tab) => tab.viewId == destinationViewId);
      final destinationIndex = preferredIndex >= 0 && preferredIndex != index
          ? preferredIndex
          : (index == 0 ? 1 : index - 1);
      context.go('/browser/tab/${tabs[destinationIndex].viewId}');
    }

    return true;
  }

  // How long a tab's row takes to collapse when it is closed. The tab is only
  // removed once this has passed, so the strip and the sidebar can animate it
  // out first.
  static const Duration closeAnimationDuration = Duration(milliseconds: 180);

  // The tabs closed this session, most recently closed last, for "reopen
  // closed tab".
  static const int _maxClosedTabs = 25;
  static final List<ClosedTabRecord> _closedTabs = <ClosedTabRecord>[];

  static bool get hasClosedTabs => _closedTabs.isNotEmpty;

  // A closed tab neither has an opener nor is one.
  static void _forgetOpener(int viewId) {
    _openerByTab.remove(viewId);
    _openerByTab.removeWhere((_, opener) => opener == viewId);
  }

  static void _rememberClosedTab(LadybirdController? controller) {
    if (controller == null) return;
    final url = controller.urlNotifier.value;
    // A tab that never left the new-tab page has nothing to bring back.
    if (url.isEmpty || url == 'about:newtab' || url == 'about:blank') return;

    _closedTabs.add(
      ClosedTabRecord(url: url, title: controller.titleNotifier.value),
    );
    if (_closedTabs.length > _maxClosedTabs) _closedTabs.removeAt(0);
  }

  static void commitCloseTab(WidgetRef ref, int viewId) {
    _forgetOpener(viewId);
    _rememberClosedTab(ref.read(browserTabProvider(viewId)));
    ref.read(browserTabControllerProvider.notifier).remove(viewId);
    ref.read(closingTabsProvider.notifier).finish(viewId);
    HistoryBitmapCache.instance.evictTab(viewId);
    TabPreviewCache.instance.evict(viewId);
  }

  // The same, for a caller whose widget may be gone by the time it runs.
  static void _commitCloseTabWith(ProviderContainer container, int viewId) {
    _forgetOpener(viewId);
    _rememberClosedTab(container.read(browserTabProvider(viewId)));
    container.read(browserTabControllerProvider.notifier).remove(viewId);
    container.read(closingTabsProvider.notifier).finish(viewId);
    HistoryBitmapCache.instance.evictTab(viewId);
    TabPreviewCache.instance.evict(viewId);
  }

  // Closes a tab the way every desktop close path should: the tab's row
  // collapses first (see [closingTabsProvider]), then the tab goes away. Call
  // this rather than [closeTabImmediately] from anything that is not a screen
  // of its own that animates the close itself.
  static Future<void> closeTab(
    BuildContext context, {
    required int currentViewId,
    required int closeViewId,
    int? destinationViewId,
  }) async {
    // Closing a tab can navigate away from the widget that asked, so nothing
    // after the first await may touch `context`.
    final container = ProviderScope.containerOf(context, listen: false);
    if (container.read(closingTabsProvider).contains(closeViewId)) return;

    final canClose = prepareCloseTabNavigation(
      context,
      currentViewId: currentViewId,
      closeViewId: closeViewId,
      tabs: container.read(browserTabControllerProvider),
      destinationViewId: destinationViewId,
    );
    if (!canClose) return;

    container.read(closingTabsProvider.notifier).begin(closeViewId);
    await Future<void>.delayed(closeAnimationDuration);
    _commitCloseTabWith(container, closeViewId);
  }

  // Opens the most recently closed tab again, in a new tab. Returns false when
  // there is nothing to reopen.
  static bool reopenClosedTab(WidgetRef ref, BuildContext context) {
    if (_closedTabs.isEmpty) return false;
    final record = _closedTabs.removeLast();
    final controller = openNewTab(ref, context);
    controller.navigate(record.url);
    return true;
  }

  // Opens an internal or external address in a tab of its own, leaving the
  // current tab where it is.
  static LadybirdController openUrlInNewTab(
    WidgetRef ref,
    BuildContext context,
    String url,
  ) {
    final controller = openNewTab(ref, context);
    controller.navigate(url);
    return controller;
  }

  static void closeTabImmediately(
    WidgetRef ref,
    BuildContext context, {
    required int currentViewId,
    required int closeViewId,
  }) {
    final tabs = ref.read(browserTabControllerProvider);
    final canClose = prepareCloseTabNavigation(
      context,
      currentViewId: currentViewId,
      closeViewId: closeViewId,
      tabs: tabs,
    );
    if (!canClose) return;

    commitCloseTab(ref, closeViewId);
  }
}

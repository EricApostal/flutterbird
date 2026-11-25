import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/windows/browser_shell.dart';
import 'package:flutterbird/features/windows/window_scope.dart';
import 'package:ladybird/ladybird.dart';

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

/// What the user does to tabs from a window's own UI. Each acts on the window
/// the widget asking is in; [BrowserShell] does the work.
class BrowserTabActions {
  static LadybirdController openNewTab(WidgetRef ref, BuildContext context) {
    return ref
        .read(browserShellProvider)
        .openTab(windowId: BrowserWindowScope.of(context));
  }

  static void showTab(BuildContext context, int viewId) {
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(browserShellProvider).showTab(viewId);
  }

  // The tab that opened [viewId], if both still exist.
  static int? openerOf(WidgetRef ref, int viewId) =>
      ref.read(browserShellProvider).openerOf(viewId);

  // How long a tab's row takes to collapse when it is closed. The tab is only
  // removed once this has passed, so the strip and the sidebar can animate it
  // out first.
  static const Duration closeAnimationDuration = Duration(milliseconds: 180);

  // Closes a tab from the tab switcher, which stays where it is, even with no
  // tab left.
  static void commitCloseTab(WidgetRef ref, int viewId) {
    ref.read(browserShellProvider).closeTab(viewId, stayPut: true);
    ref.read(closingTabsProvider.notifier).finish(viewId);
  }

  // Closes a tab the way every desktop close path should: the tab's row
  // collapses first (see [closingTabsProvider]), then the tab goes away. Call
  // this rather than [closeTabImmediately] from anything that is not a screen
  // of its own that animates the close itself.
  //
  // If it is the tab on screen, [destinationViewId] is shown instead of its
  // neighbour.
  static Future<void> closeTab(
    BuildContext context, {
    required int currentViewId,
    required int closeViewId,
    int? destinationViewId,
  }) async {
    // Closing a tab can take the widget that asked off screen, or its whole
    // window, so nothing after the first await may touch `context`.
    final container = ProviderScope.containerOf(context, listen: false);
    if (container.read(closingTabsProvider).contains(closeViewId)) return;

    final shell = container.read(browserShellProvider);
    final window = shell.session.windowOfTab(closeViewId);
    if (window == null) return;

    // A window's last tab takes the window with it: there is no row to see
    // collapse.
    if (window.tabIds.length == 1) {
      shell.closeTab(closeViewId);
      return;
    }

    if (closeViewId == currentViewId) {
      final destination =
          destinationViewId != null &&
              destinationViewId != closeViewId &&
              window.tabIds.contains(destinationViewId)
          ? destinationViewId
          : null;
      final index = window.tabIds.indexOf(closeViewId);
      shell.showTab(destination ?? window.tabIds[index == 0 ? 1 : index - 1]);
    }

    container.read(closingTabsProvider.notifier).begin(closeViewId);
    await Future<void>.delayed(closeAnimationDuration);
    shell.closeTab(closeViewId);
    container.read(closingTabsProvider.notifier).finish(closeViewId);
  }

  // Opens the most recently closed tab again, in a new tab. Returns false when
  // there is nothing to reopen.
  static bool reopenClosedTab(WidgetRef ref, BuildContext context) {
    return ref
        .read(browserShellProvider)
        .reopenClosedTab(windowId: BrowserWindowScope.of(context));
  }

  // Opens an internal or external address in a tab of its own, leaving the
  // current tab where it is.
  static LadybirdController openUrlInNewTab(
    WidgetRef ref,
    BuildContext context,
    String url,
  ) {
    return ref
        .read(browserShellProvider)
        .openTab(windowId: BrowserWindowScope.of(context), url: url);
  }

  static void closeTabImmediately(WidgetRef ref, {required int closeViewId}) {
    ref.read(browserShellProvider).closeTab(closeViewId);
  }
}

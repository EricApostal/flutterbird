import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/mobile_omnibox_bar.dart';
import 'package:flutterbird/features/browser/components/tab_swipe_back_stack.dart';
import 'package:flutterbird/features/browser/state/fullscreen_mode.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_history.dart';

class MobileBrowserLayout extends ConsumerWidget {
  final int viewId;

  const MobileBrowserLayout({super.key, required this.viewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTabController = ref.watch(browserTabProvider(viewId));
    final isFullscreen = ref.watch(browserFullscreenModeControllerProvider);

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    // Going back goes through the tab's own history first (the swipe stack
    // below takes the system back button while there is any). Once it has none
    // left, a tab that a page opened closes and hands the user back to the tab
    // that opened it, like in a browser. Any other tab lets the back button
    // through, which leaves the app.
    final historyState = ref.watch(tabHistoryControllerProvider(viewId));
    final currentStep = historyState.effectiveCurrentStep;
    final canGoBackInTab =
        currentStep != null && historyState.canPopFrom(currentStep);
    final openerViewId = BrowserTabActions.openerOf(ref, viewId);
    final backClosesTab =
        openerViewId != null && !canGoBackInTab && !isFullscreen;

    return PopScope(
      canPop: !backClosesTab,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || openerViewId == null) return;
        BrowserTabActions.closeTab(
          context,
          currentViewId: viewId,
          closeViewId: viewId,
          destinationViewId: openerViewId,
        );
      },
      child: Scaffold(
        body: Column(
          children: [
            if (!isFullscreen)
              MobileOmniboxBar(currentTabController: currentTabController),
            // Keyed by the tab: each tab gets its own stack of history pages, so
            // switching tabs never animates one tab's pages into another's.
            Expanded(
              child: TabSwipeBackStack(key: ValueKey(viewId), viewId: viewId),
            ),
          ],
        ),
      ),
    );
  }
}

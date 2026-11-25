import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/mobile_omnibox_bar.dart';
import 'package:flutterbird/features/browser/state/fullscreen_mode.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_history.dart';
import 'package:flutterbird/features/windows/window_scope.dart';

class MobileBrowserLayout extends ConsumerWidget {
  final int viewId;

  const MobileBrowserLayout({super.key, required this.viewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTabController = ref.watch(browserTabProvider(viewId));
    final windowId = BrowserWindowScope.of(context);
    final isFullscreen = ref.watch(
      browserFullscreenModeControllerProvider(windowId),
    );

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    // The back button does what it does in a browser, in this order:
    //  1. The page has history behind it: go back through it. That is the engine
    //     going back, and nothing else: the view shows the page it navigates to,
    //     with no animation of ours, because there is no stack of pages here to
    //     animate (a stack of snapshots pushed one per link and then fought the
    //     engine's own navigation, which showed as jank).
    //  2. The tab was opened by a page and has no history left: close it and go
    //     back to the tab that opened it.
    //  3. Otherwise let the back button through, which leaves the app.
    // While the page is fullscreen, the back button exits that instead
    // (BrowserWindowScreen handles it).
    final historyState = ref.watch(tabHistoryControllerProvider(viewId));
    final currentStep = historyState.effectiveCurrentStep;
    final hasHistory =
        currentStep != null && historyState.canPopFrom(currentStep);
    final openerViewId = BrowserTabActions.openerOf(ref, viewId);
    final goesBack = !isFullscreen && hasHistory;
    final closesTab = !isFullscreen && !hasHistory && openerViewId != null;

    return PopScope(
      canPop: !(goesBack || closesTab),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (goesBack) {
          currentTabController.goBack();
        } else if (closesTab) {
          BrowserTabActions.closeTab(
            context,
            currentViewId: viewId,
            closeViewId: viewId,
            destinationViewId: openerViewId,
          );
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            if (!isFullscreen)
              MobileOmniboxBar(currentTabController: currentTabController),
            Expanded(
              child: BrowserWindow(
                key: BrowserWindow.keyFor(windowId, viewId),
                viewId: viewId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

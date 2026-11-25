import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/screens/browser.dart';
import 'package:flutterbird/features/windows/popup_window_screen.dart';
import 'package:flutterbird/features/windows/window_scope.dart';
import 'package:flutterbird/features/windows/window_system.dart';
import 'package:ladybird/ladybird.dart';

/// A window's page: the tab its session says is showing, in a browser window
/// or in a popup. Where there is one window, the route says this instead.
class DesktopWindowHome extends ConsumerWidget {
  const DesktopWindowHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windowId = BrowserWindowScope.of(context);
    final window = ref.watch(browserWindowProvider(windowId));
    final tabId = window?.activeTabId;
    final tab = tabId == null ? null : ref.watch(browserTabProvider(tabId));

    // A window whose only tab is docked in another, until the drag ends.
    if (window == null || tab == null) {
      return ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
    }

    return _WindowTitle(
      windowId: windowId,
      tab: tab,
      child: window.isPopup
          ? PopupWindowScreen(viewId: tab.viewId)
          : BrowserWindowScreen(viewId: tab.viewId),
    );
  }
}

/// Names the window after its page: in a popup's title bar, and in the Window
/// menu and Mission Control for the rest.
class _WindowTitle extends ConsumerWidget {
  const _WindowTitle({
    required this.windowId,
    required this.tab,
    required this.child,
  });

  final int windowId;
  final LadybirdController tab;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<String>(
      valueListenable: tab.titleNotifier,
      child: child,
      builder: (context, title, child) {
        final windows = ref.read(windowSystemProvider);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) windows.setTitle(windowId, title);
        });
        return child!;
      },
    );
  }
}

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/mobile_omnibox_bar.dart';
import 'package:flutterbird/features/browser/components/mobile_tab_switcher.dart';

final mobileTabSwitcherStateProvider = StateProvider<bool>((ref) => false);

class MobileBrowserLayout extends ConsumerWidget {
  final int viewId;

  const MobileBrowserLayout({super.key, required this.viewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTabSwitcherOpen = ref.watch(mobileTabSwitcherStateProvider);
    final currentTabController = ref.watch(browserTabProvider(viewId));
    final padding = MediaQuery.paddingOf(context);

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: padding.top),
              MobileOmniboxBar(currentTabController: currentTabController),
              Expanded(child: BrowserWindow(viewId: viewId)),
            ],
          ),
          if (isTabSwitcherOpen)
            Positioned.fill(
              child: Container(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    SizedBox(height: padding.top),
                    const Expanded(child: MobileTabSwitcher()),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

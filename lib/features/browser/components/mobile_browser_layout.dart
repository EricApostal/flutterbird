import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/mobile_omnibox_bar.dart';
import 'package:flutterbird/features/browser/state/fullscreen_mode.dart';

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

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              if (!isFullscreen)
                MobileOmniboxBar(currentTabController: currentTabController),
              Expanded(child: BrowserWindow(viewId: viewId)),
            ],
          ),
          if (isFullscreen)
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Exit fullscreen',
                      icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                      onPressed: () {
                        ref
                            .read(browserFullscreenModeControllerProvider.notifier)
                            .exit();
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

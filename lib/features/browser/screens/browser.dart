import 'dart:async';
import 'dart:io';
import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/mobile_browser_layout.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_bar.dart';
import 'package:flutterbird/features/browser/components/desktop/tabs/tab_bar.dart';
import 'package:flutterbird/features/browser/components/desktop/tabs/vertical_tab_sidebar.dart';
import 'package:flutterbird/features/browser/state/fullscreen_mode.dart';
import 'package:flutterbird/features/browser/state/history_bitmap_cache.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_layout_mode.dart';
import 'package:ladybird/ladybird.dart';

class BrowserWindowScreen extends ConsumerStatefulWidget {
  final int viewId;
  const BrowserWindowScreen({super.key, required this.viewId});

  @override
  ConsumerState<BrowserWindowScreen> createState() =>
      _BrowserWindowScreenState();
}

class _BrowserWindowScreenState extends ConsumerState<BrowserWindowScreen> {
  static const Duration _kLayoutTransitionDuration = Duration(
    milliseconds: 240,
  );
  static const Duration _kFullscreenHintDuration = Duration(seconds: 3);

  bool _showFullscreenHint = false;
  Timer? _fullscreenHintTimer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    // Every tab's view texture is created fresh here (each tab is its own
    // route), so a switched-to tab starts with a texture that has nothing to
    // paint: hand libbird this tab's last presented frame to cover that, from
    // the same snapshots the swipe-back stack is built from.
    LadybirdView.lastFrameProvider = HistoryBitmapCache.instance.cloneLastFrame;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _fullscreenHintTimer?.cancel();
    super.dispose();
  }

  bool _isPrimaryShortcutModifierPressed() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final hasControl =
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final hasMeta =
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    return hasControl || hasMeta;
  }

  bool _isShiftPressed() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    return pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
  }

  void _openNewTab() {
    BrowserTabActions.openNewTab(ref, context);
  }

  void _closeCurrentTab() {
    BrowserTabActions.closeTabImmediately(
      ref,
      context,
      currentViewId: widget.viewId,
      closeViewId: widget.viewId,
    );
  }

  void _toggleTabLayoutMode() {
    ref.read(browserTabLayoutModeControllerProvider.notifier).toggle();
  }

  // A platform-level exit gesture (tapping the overlay button, an Android
  // back gesture) rather than the page exiting on its own. Restores our own
  // chrome/window immediately rather than waiting on the page to confirm —
  // see BrowserFullscreenModeController.exitFromUi for why.
  void _requestExitFullscreen() {
    ref.read(browserFullscreenModeControllerProvider.notifier).exitFromUi();
  }

  void _showFullscreenHintBriefly() {
    _fullscreenHintTimer?.cancel();
    setState(() => _showFullscreenHint = true);
    _fullscreenHintTimer = Timer(_kFullscreenHintDuration, () {
      if (!mounted) return;
      setState(() => _showFullscreenHint = false);
    });
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!_isPrimaryShortcutModifierPressed()) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyT) {
      _openNewTab();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      _closeCurrentTab();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyS && _isShiftPressed()) {
      _toggleTabLayoutMode();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewId = widget.viewId;
    final layoutMode = ref.watch(browserTabLayoutModeControllerProvider);
    final isVerticalLayout = layoutMode == BrowserTabLayoutMode.vertical;
    final currentTabController = ref.watch(browserTabProvider(viewId));
    final isFullscreen = ref.watch(browserFullscreenModeControllerProvider);

    ref.listen<bool>(browserFullscreenModeControllerProvider, (previous, next) {
      if (next) {
        _showFullscreenHintBriefly();
      } else if (_showFullscreenHint) {
        _fullscreenHintTimer?.cancel();
        setState(() => _showFullscreenHint = false);
      }
    });

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    // While fullscreen, a platform back gesture/button should exit
    // fullscreen (like every other browser) instead of doing nothing or
    // navigating away.
    Widget withFullscreenBackHandling(Widget child) {
      return PopScope(
        canPop: !isFullscreen,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _requestExitFullscreen();
        },
        child: child,
      );
    }

    if (Platform.isAndroid) {
      return withFullscreenBackHandling(MobileBrowserLayout(viewId: viewId));
    }

    final padding = MediaQuery.paddingOf(context);
    final showSidebar = isVerticalLayout && !isFullscreen;

    return withFullscreenBackHandling(
      Scaffold(
        backgroundColor: Color.lerp(
          Colors.black,
          theme.colorScheme.primaryContainer,
          0.5,
        ),
        body: Stack(
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: _kLayoutTransitionDuration,
                  curve: Curves.easeOutCubic,
                  width: showSidebar
                      ? BrowserVerticalTabSidebar.sidebarWidth
                      : 0,
                  child: IgnorePointer(
                    ignoring: !showSidebar,
                    child: ClipRect(
                      child: AnimatedSlide(
                        duration: _kLayoutTransitionDuration,
                        curve: Curves.easeOutCubic,
                        offset: showSidebar
                            ? Offset.zero
                            : const Offset(-0.08, 0),
                        child: AnimatedOpacity(
                          duration: _kLayoutTransitionDuration,
                          curve: Curves.easeOut,
                          opacity: showSidebar ? 1 : 0,
                          child: BrowserVerticalTabSidebar(
                            currentViewId: viewId,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: isFullscreen
                      ? BrowserWindow(
                          key: GlobalObjectKey<State<BrowserWindow>>(viewId),
                          viewId: viewId,
                        )
                      // No cross-fade between the two layouts: it faded the
                      // page itself, so switching the tab layout showed the
                      // window behind the content for the duration. The sidebar
                      // still animates; the page is simply always at full
                      // opacity.
                      : (isVerticalLayout
                            ? Column(
                                key: const ValueKey('vertical-layout'),
                                children: [
                                  BrowserOmniboxBar(
                                    currentTabController: currentTabController,
                                  ),
                                  Expanded(
                                    child: Container(
                                      color: theme.colorScheme.primaryContainer,
                                      child: ClipRRect(
                                        borderRadius: .only(
                                          topLeft: .circular(8),
                                        ),
                                        child: BrowserWindow(
                                          key:
                                              GlobalObjectKey<
                                                State<BrowserWindow>
                                              >(viewId),
                                          viewId: viewId,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                key: const ValueKey('horizontal-layout'),
                                children: [
                                  SizedBox(height: padding.top),
                                  BrowserTabBar(currentViewId: viewId),
                                  Expanded(
                                    child: BrowserWindow(
                                      key:
                                          GlobalObjectKey<State<BrowserWindow>>(
                                            viewId,
                                          ),
                                      viewId: viewId,
                                    ),
                                  ),
                                ],
                              )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Shown while the page has a DOM Fullscreen API element active (e.g. a
// fullscreen <video>), giving mouse/touch users a way out beyond Escape.
class _FullscreenExitOverlay extends StatelessWidget {
  final bool showHint;
  final VoidCallback onExit;

  const _FullscreenExitOverlay({required this.showHint, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 12,
          right: 12,
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Exit fullscreen',
              icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
              onPressed: onExit,
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: showHint ? 1 : 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Press Esc to exit fullscreen',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

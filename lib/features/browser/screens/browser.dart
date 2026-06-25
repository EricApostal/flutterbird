import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/omnibox_bar.dart';
import 'package:flutterbird/features/browser/components/tab_bar.dart';
import 'package:flutterbird/features/browser/components/vertical_tab_sidebar.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:flutterbird/features/browser/state/tab_layout_mode.dart';

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

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
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
    final viewId = widget.viewId;
    final layoutMode = ref.watch(browserTabLayoutModeControllerProvider);
    final isVerticalLayout = layoutMode == BrowserTabLayoutMode.vertical;
    final currentTabController = ref.watch(browserTabProvider(viewId));

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    final padding = MediaQuery.paddingOf(context);

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: _kLayoutTransitionDuration,
            curve: Curves.easeOutCubic,
            width: isVerticalLayout
                ? BrowserVerticalTabSidebar.sidebarWidth
                : 0,
            child: IgnorePointer(
              ignoring: !isVerticalLayout,
              child: ClipRect(
                child: AnimatedSlide(
                  duration: _kLayoutTransitionDuration,
                  curve: Curves.easeOutCubic,
                  offset: isVerticalLayout
                      ? Offset.zero
                      : const Offset(-0.08, 0),
                  child: AnimatedOpacity(
                    duration: _kLayoutTransitionDuration,
                    curve: Curves.easeOut,
                    opacity: isVerticalLayout ? 1 : 0,
                    child: BrowserVerticalTabSidebar(currentViewId: viewId),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: _kLayoutTransitionDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0.02, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: isVerticalLayout
                  ? Column(
                      key: const ValueKey('vertical-layout'),
                      children: [
                        BrowserOmniboxBar(
                          currentTabController: currentTabController,
                        ),
                        Expanded(child: BrowserWindow(viewId: viewId)),
                      ],
                    )
                  : Column(
                      key: const ValueKey('horizontal-layout'),
                      children: [
                        SizedBox(height: padding.top),
                        BrowserTabBar(currentViewId: viewId),
                        Expanded(child: BrowserWindow(viewId: viewId)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

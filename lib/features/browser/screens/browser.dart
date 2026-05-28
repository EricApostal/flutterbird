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
    final currentTabController = ref.watch(browserTabProvider(viewId));

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    if (layoutMode == BrowserTabLayoutMode.horizontal) {
      return Scaffold(
        body: Column(
          children: [
            BrowserTabBar(currentViewId: viewId),
            Expanded(child: BrowserWindow(viewId: viewId)),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          BrowserVerticalTabSidebar(currentViewId: viewId),
          Expanded(
            child: Column(
              children: [
                BrowserOmniboxBar(currentTabController: currentTabController),
                Expanded(child: BrowserWindow(viewId: viewId)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

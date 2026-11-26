import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_url_text.dart';
import 'package:flutterbird/features/browser/components/desktop/site_info/site_info_button.dart';
import 'package:flutterbird/features/browser/state/fullscreen_mode.dart';
import 'package:flutterbird/features/windows/browser_shell.dart';
import 'package:flutterbird/features/windows/window_scope.dart';
import 'package:flutterbird/features/windows/window_system.dart';
import 'package:ladybird/ladybird.dart';

/// What a popup window shows: one page, with no tabs and nowhere to type an
/// address. It does say where the page is, since a popup is often where a
/// password gets typed.
class PopupWindowScreen extends ConsumerStatefulWidget {
  const PopupWindowScreen({required this.viewId, super.key});

  final int viewId;

  @override
  ConsumerState<PopupWindowScreen> createState() => _PopupWindowScreenState();
}

class _PopupWindowScreenState extends ConsumerState<PopupWindowScreen> {
  late int _windowId;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _windowId = BrowserWindowScope.of(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  // Keyboard handlers hear every window's keys, so each acts only on its own.
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isMetaPressed && !keyboard.isControlPressed) return false;
    if (!ref.read(windowSystemProvider).claimShortcut(_windowId, event)) {
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      ref.read(browserShellProvider).closeWindow(_windowId);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      ref.read(browserShellProvider).openWindow();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tab = ref.watch(browserTabProvider(widget.viewId));
    if (tab == null) return const SizedBox.shrink();
    final isFullscreen = ref.watch(
      browserFullscreenModeControllerProvider(_windowId),
    );

    return Scaffold(
      backgroundColor: omniboxSurfaceColor(theme),
      body: Column(
        children: [
          if (!isFullscreen) _PopupLocationBar(tab: tab),
          Expanded(
            child: BrowserWindow(
              key: BrowserWindow.keyFor(_windowId, widget.viewId),
              viewId: widget.viewId,
            ),
          ),
        ],
      ),
    );
  }
}

class _PopupLocationBar extends StatelessWidget {
  const _PopupLocationBar({required this.tab});

  final LadybirdController tab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: BrowserShell.popupLocationBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SiteInfoButton(tab: tab),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: tab.urlNotifier,
                  builder: (context, url, _) => Text.rich(
                    styledUrlSpan(theme, url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

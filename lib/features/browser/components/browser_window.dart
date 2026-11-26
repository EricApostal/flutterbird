import 'dart:ui' as ui;

import 'package:bird_core/bird_core.dart';
import 'package:bird_devtools/bird_devtools.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show Theme;
import 'package:rubisco_browser/features/browser/components/browser_context_menu.dart';
import 'package:rubisco_browser/features/browser/components/tab_loading_bar.dart';
import 'package:rubisco_browser/features/devtools/browser_devtools.dart';
import 'package:rubisco_browser/features/new_tab/new_tab_page.dart';
import 'package:rubisco_browser/features/settings/settings_page.dart';
import 'package:rubisco_browser/features/browser/state/fullscreen_mode.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';
import 'package:ladybird/ladybird.dart';

class BrowserWindow extends ConsumerStatefulWidget {
  final int viewId;
  const BrowserWindow({super.key, required this.viewId});

  // The keys every BrowserWindow is made with, by window and tab. A key per
  // window keeps the page's state when the window changes its layout, while a
  // tab that moves to another window gets new state there: for a moment both
  // windows can have one.
  static final Map<(int, int), GlobalKey<State<BrowserWindow>>> _keys = {};

  static GlobalKey<State<BrowserWindow>> keyFor(int windowId, int viewId) =>
      _keys.putIfAbsent((
        windowId,
        viewId,
      ), GlobalKey<State<BrowserWindow>>.new);

  // Called when a tab closes.
  static void forgetTab(int viewId) {
    _keys.removeWhere((id, _) => id.$2 == viewId);
  }

  // Captures a snapshot of the live web content currently shown for
  // [viewId], if that tab's BrowserWindow is mounted in any window. Returns
  // null if the tab isn't mounted or the capture fails (first frame not yet
  // painted, etc); callers should fall back to a placeholder.
  //
  // [maxWidth] caps the snapshot's width in physical pixels, so a thumbnail is
  // rendered at thumbnail size instead of being read back in full and
  // downscaled afterwards.
  static Future<ui.Image?> captureSnapshotFor(int viewId, {double? maxWidth}) {
    for (final entry in _keys.entries) {
      if (entry.key.$2 != viewId) continue;
      final state = entry.value.currentState;
      if (state is _BrowserWindowState) {
        return state._captureSnapshot(maxWidth: maxWidth);
      }
    }
    return Future.value(null);
  }

  @override
  ConsumerState<BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends ConsumerState<BrowserWindow> {
  final GlobalKey _viewKey = GlobalKey();
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  bool _contextMenuVisible = false;
  LadybirdController? _boundController;

  Future<ui.Image?> _captureSnapshot({double? maxWidth}) async {
    final renderObject = _repaintBoundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    if (!renderObject.attached || renderObject.debugNeedsPaint) return null;

    try {
      var pixelRatio = _repaintBoundaryKey.currentContext != null
          ? MediaQuery.devicePixelRatioOf(_repaintBoundaryKey.currentContext!)
          : 1.0;
      final width = renderObject.size.width;
      if (maxWidth != null && width > 0 && width * pixelRatio > maxWidth) {
        pixelRatio = maxWidth / width;
      }
      return await renderObject.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      return null;
    }
  }

  late final void Function(LadybirdContextMenuRequest)
  _onContextMenuRequestCallback = _onContextMenuRequest;
  late final void Function(bool) _onFullscreenChangeCallback =
      _onFullscreenChange;

  // What pages do to tabs and windows is the browser shell's business, which
  // hears of it whether or not the tab is on screen. What needs this widget is
  // what is about the page on screen.
  void _bindController(LadybirdController controller) {
    if (identical(_boundController, controller)) return;

    _unbindController();
    _boundController = controller;
    controller.onContextMenuRequest = _onContextMenuRequestCallback;
    controller.onFullscreenChange = _onFullscreenChangeCallback;
  }

  // A tab that moved to another window has been bound by its widget there
  // before this one goes, so only what is still this widget's is taken back.
  void _unbindController() {
    final controller = _boundController;
    if (controller == null) return;
    if (controller.onContextMenuRequest == _onContextMenuRequestCallback) {
      controller.onContextMenuRequest = null;
    }
    if (controller.onFullscreenChange == _onFullscreenChangeCallback) {
      controller.onFullscreenChange = null;
    }
  }

  void _onFullscreenChange(bool isFullscreen) {
    if (!mounted) {
      print(
        '[Fullscreen] BrowserWindow._onFullscreenChange dropped: not mounted',
      );
      return;
    }
    final controller = _boundController;
    if (controller == null) {
      print(
        '[Fullscreen] BrowserWindow._onFullscreenChange dropped: no bound controller',
      );
      return;
    }
    ref
        .read(
          browserFullscreenModeControllerProvider(
            BrowserWindowScope.of(context),
          ).notifier,
        )
        .syncFromEngine(controller, isFullscreen);
  }

  @override
  void dispose() {
    _unbindController();
    super.dispose();
  }

  List<BrowserContextMenuItem> _mapContextMenuEntries(
    List<LadybirdContextMenuEntry> entries,
  ) {
    final mapped = <BrowserContextMenuItem>[];

    for (final entry in entries) {
      if (entry.isSeparator) {
        mapped.add(const BrowserContextMenuItem.separator());
        continue;
      }

      if (entry.isSubmenu) {
        mapped.add(
          BrowserContextMenuItem.submenu(
            label: entry.text,
            children: _mapContextMenuEntries(entry.items),
          ),
        );
        continue;
      }

      if (!entry.isAction || entry.actionToken == null) continue;

      mapped.add(
        BrowserContextMenuItem.action(
          label: entry.text,
          value: entry.actionToken,
          enabled: entry.enabled,
          checkable: entry.checkable,
          checked: entry.checked,
        ),
      );
    }

    return mapped;
  }

  Future<void> _onContextMenuRequest(LadybirdContextMenuRequest request) async {
    if (!mounted || _contextMenuVisible) return;

    final controller = _boundController;
    if (controller == null) return;

    final viewContext = _viewKey.currentContext;
    if (viewContext == null) return;

    final viewRenderObject = viewContext.findRenderObject();
    if (viewRenderObject is! RenderBox) return;

    final density = MediaQuery.devicePixelRatioOf(viewContext);
    final localPosition = Offset(request.x / density, request.y / density);
    final globalPosition = viewRenderObject.localToGlobal(localPosition);

    final items = _mapContextMenuEntries(request.items);
    if (items.isEmpty) return;

    _contextMenuVisible = true;
    try {
      final selectedValue = await BrowserContextMenuPresenter.show(
        context: context,
        anchorRect: Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        items: items,
      );

      if (selectedValue is int) {
        controller.activateContextMenuAction(selectedValue);
      }
    } finally {
      _contextMenuVisible = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // The desktop's colours, or Android's Material ones.
    final brightness =
        BirdTheme.maybeOf(context)?.brightness ?? Theme.of(context).brightness;
    final controller = ref.watch(browserTabProvider(widget.viewId));
    if (controller == null) {
      return const SizedBox.shrink();
    }

    _bindController(controller);
    controller.updateColorScheme(brightness);

    final windowId = BrowserWindowScope.of(context);
    final isFullscreen = ref.watch(
      browserFullscreenModeControllerProvider(windowId),
    );
    // Only the window being used may take the keyboard: asking for it from
    // another would bring that one forward.
    final isFocusedWindow =
        ref.read(browserSessionProvider).focusedWindowId == windowId;

    final page = Stack(
      // The page keeps the constraints it always had; the bar only overlays it.
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(
          key: _repaintBoundaryKey,
          child: ValueListenableBuilder<String>(
            valueListenable: controller.urlNotifier,
            // The view stays as it is under the new tab page, which is drawn
            // over it until the tab goes somewhere.
            child: KeyedSubtree(
              key: _viewKey,
              child: LadybirdView(
                controller: controller,
                autofocus: isFocusedWindow,
              ),
            ),
            builder: (context, url, view) => Stack(
              fit: StackFit.passthrough,
              children: [
                view!,
                if (controller.isOnNewTabPage)
                  Positioned.fill(
                    child: NewTabPage(
                      key: ValueKey(controller.viewId),
                      tab: controller,
                    ),
                  ),
                if (controller.isOnSettingsPage)
                  const Positioned.fill(child: SettingsPage()),
              ],
            ),
          ),
        ),
        // Outside the repaint boundary, so a snapshot of the page (for tab
        // previews) never has a half-finished bar in it.
        if (!isFullscreen)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TabLoadingBar(isLoading: controller.isLoadingNotifier),
          ),
      ],
    );

    final devTools = ref.read(devToolsProvider);
    if (devTools == null) return page;
    return DevToolsDockLayout(
      manager: devTools,
      tabId: widget.viewId,
      hidden: isFullscreen,
      autoBrightness: brightness,
      page: page,
    );
  }
}

import 'dart:ui' as ui;

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_context_menu.dart';
import 'package:flutterbird/features/browser/components/tab_loading_bar.dart';
import 'package:flutterbird/features/browser/state/fullscreen_mode.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:ladybird/ladybird.dart';

class BrowserWindow extends ConsumerStatefulWidget {
  final int viewId;
  const BrowserWindow({super.key, required this.viewId});

  // Captures a snapshot of the live web content currently shown for
  // [viewId], if that tab's BrowserWindow is mounted anywhere in the tree --
  // resolved via the same GlobalObjectKey<State<BrowserWindow>>(viewId)
  // convention already used at every BrowserWindow(...) call site. Returns
  // null if the tab isn't mounted or the capture fails (first frame not yet
  // painted, etc); callers should fall back to a placeholder.
  //
  // [maxWidth] caps the snapshot's width in physical pixels, so a thumbnail is
  // rendered at thumbnail size instead of being read back in full and
  // downscaled afterwards.
  static Future<ui.Image?> captureSnapshotFor(int viewId, {double? maxWidth}) {
    final state = GlobalObjectKey<State<BrowserWindow>>(viewId).currentState;
    if (state is! _BrowserWindowState) return Future.value(null);
    return state._captureSnapshot(maxWidth: maxWidth);
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
  late final void Function(int, bool) _onNewWebViewCallback = _onNewWebView;
  late final void Function(bool) _onFullscreenChangeCallback =
      _onFullscreenChange;

  void _bindController(LadybirdController controller) {
    if (identical(_boundController, controller)) return;

    if (_boundController != null) {
      _boundController!.onContextMenuRequest = null;
      _boundController!.onNewWebView = null;
      _boundController!.onFullscreenChange = null;
    }

    _boundController = controller;
    _boundController!.onContextMenuRequest = _onContextMenuRequestCallback;
    _boundController!.onNewWebView = _onNewWebViewCallback;
    _boundController!.onFullscreenChange = _onFullscreenChangeCallback;
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
        .read(browserFullscreenModeControllerProvider.notifier)
        .syncFromEngine(controller, isFullscreen);
  }

  @override
  void dispose() {
    if (_boundController != null) {
      _boundController!.onContextMenuRequest = null;
      _boundController!.onNewWebView = null;
      _boundController!.onFullscreenChange = null;
    }
    super.dispose();
  }

  void _onNewWebView(int newViewId, bool activateTab) {
    if (!mounted) return;
    BrowserTabActions.openExistingTab(
      ref,
      context,
      newViewId,
      activate: activateTab,
      openerViewId: widget.viewId,
    );
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
    final theme = Theme.of(context);
    final controller = ref.watch(browserTabProvider(widget.viewId));
    if (controller == null) {
      return const SizedBox.shrink();
    }

    _bindController(controller);
    controller.updateColorScheme(Theme.of(context).brightness);

    final isFullscreen = ref.watch(browserFullscreenModeControllerProvider);

    return Stack(
      // The page keeps the constraints it always had; the bar only overlays it.
      fit: StackFit.passthrough,
      children: [
        RepaintBoundary(
          key: _repaintBoundaryKey,
          child: KeyedSubtree(
            key: _viewKey,
            child: LadybirdView(controller: controller),
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
  }
}

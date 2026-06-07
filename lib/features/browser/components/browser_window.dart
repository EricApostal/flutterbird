import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_context_menu.dart';
import 'package:flutterbird/features/browser/state/tab_actions.dart';
import 'package:ladybird/ladybird.dart';

class BrowserWindow extends ConsumerStatefulWidget {
  final int viewId;
  const BrowserWindow({super.key, required this.viewId});

  @override
  ConsumerState<BrowserWindow> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends ConsumerState<BrowserWindow> {
  final GlobalKey _viewKey = GlobalKey();
  bool _contextMenuVisible = false;
  LadybirdController? _boundController;

  late final void Function(LadybirdContextMenuRequest)
  _onContextMenuRequestCallback = _onContextMenuRequest;
  late final void Function(int, bool) _onNewWebViewCallback = _onNewWebView;

  void _bindController(LadybirdController controller) {
    if (identical(_boundController, controller)) return;

    if (_boundController != null) {
      _boundController!.onContextMenuRequest = null;
      _boundController!.onNewWebView = null;
    }

    _boundController = controller;
    _boundController!.onContextMenuRequest = _onContextMenuRequestCallback;
    _boundController!.onNewWebView = _onNewWebViewCallback;
  }

  @override
  void dispose() {
    if (_boundController != null) {
      _boundController!.onContextMenuRequest = null;
      _boundController!.onNewWebView = null;
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
    final controller = ref.watch(browserTabProvider(widget.viewId));
    if (controller == null) {
      return const SizedBox.shrink();
    }

    _bindController(controller);

    return KeyedSubtree(
      key: _viewKey,
      child: LadybirdView(controller: controller),
    );
  }
}

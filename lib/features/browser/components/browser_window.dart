import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  List<PopupMenuEntry<int>> _buildContextMenuEntries(
    List<LadybirdContextMenuEntry> entries,
    ThemeData theme, {
    int depth = 0,
  }) {
    final popupEntries = <PopupMenuEntry<int>>[];

    for (final entry in entries) {
      if (entry.isSeparator) {
        if (popupEntries.isNotEmpty && popupEntries.last is! PopupMenuDivider) {
          popupEntries.add(
            PopupMenuDivider(
              height: 8,
              color: theme.colorScheme.outlineVariant.withOpacity(0.45),
            ),
          );
        }
        continue;
      }

      if (entry.isSubmenu) {
        if (entry.text.isNotEmpty) {
          popupEntries.add(
            PopupMenuItem<int>(
              enabled: false,
              height: 28,
              padding: EdgeInsets.only(left: 10 + (depth * 10), right: 10),
              child: Text(
                entry.text,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.25,
                ),
              ),
            ),
          );
        }

        popupEntries.addAll(
          _buildContextMenuEntries(entry.items, theme, depth: depth + 1),
        );
        continue;
      }

      if (!entry.isAction || entry.actionToken == null) continue;

      popupEntries.add(
        PopupMenuItem<int>(
          value: entry.actionToken,
          enabled: entry.enabled,
          height: 32,
          padding: EdgeInsets.only(left: 8 + (depth * 10), right: 8),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: entry.checkable && entry.checked
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: theme.colorScheme.onSurface,
                      )
                    : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  entry.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: entry.enabled
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurface.withOpacity(0.45),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    while (popupEntries.isNotEmpty && popupEntries.first is PopupMenuDivider) {
      popupEntries.removeAt(0);
    }
    while (popupEntries.isNotEmpty && popupEntries.last is PopupMenuDivider) {
      popupEntries.removeLast();
    }

    return popupEntries;
  }

  Future<void> _onContextMenuRequest(LadybirdContextMenuRequest request) async {
    if (!mounted || _contextMenuVisible) return;

    final controller = _boundController;
    if (controller == null) return;

    final viewContext = _viewKey.currentContext;
    if (viewContext == null) return;

    final viewRenderObject = viewContext.findRenderObject();
    if (viewRenderObject is! RenderBox) return;

    final overlayRenderObject = Overlay.of(context).context.findRenderObject();
    if (overlayRenderObject is! RenderBox) return;

    final density = MediaQuery.devicePixelRatioOf(viewContext);
    final localPosition = Offset(request.x / density, request.y / density);
    final globalPosition = viewRenderObject.localToGlobal(localPosition);

    final theme = Theme.of(context);
    final items = _buildContextMenuEntries(request.items, theme);
    if (items.isEmpty) return;

    _contextMenuVisible = true;
    try {
      final selectedActionToken = await showMenu<int>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
          Offset.zero & overlayRenderObject.size,
        ),
        color: theme.colorScheme.surfaceContainerHigh,
        elevation: 14,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.45),
            width: 0.8,
          ),
        ),
        items: items,
      );

      if (selectedActionToken != null) {
        controller.activateContextMenuAction(selectedActionToken);
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

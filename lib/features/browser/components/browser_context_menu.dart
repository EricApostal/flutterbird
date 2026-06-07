import 'package:flutter/material.dart';

enum BrowserContextMenuItemKind { action, separator, submenu }

class BrowserContextMenuItem {
  const BrowserContextMenuItem.action({
    required this.label,
    this.value,
    this.enabled = true,
    this.checkable = false,
    this.checked = false,
  }) : kind = BrowserContextMenuItemKind.action,
       children = const [];

  const BrowserContextMenuItem.separator()
    : kind = BrowserContextMenuItemKind.separator,
      label = '',
      value = null,
      enabled = false,
      checkable = false,
      checked = false,
      children = const [];

  const BrowserContextMenuItem.submenu({
    required this.label,
    required this.children,
  }) : kind = BrowserContextMenuItemKind.submenu,
       value = null,
       enabled = false,
       checkable = false,
       checked = false;

  final BrowserContextMenuItemKind kind;
  final String label;
  final Object? value;
  final bool enabled;
  final bool checkable;
  final bool checked;
  final List<BrowserContextMenuItem> children;

  bool get isAction => kind == BrowserContextMenuItemKind.action;
  bool get isSeparator => kind == BrowserContextMenuItemKind.separator;
  bool get isSubmenu => kind == BrowserContextMenuItemKind.submenu;
}

class BrowserContextMenuPresenter {
  static Future<Object?> show({
    required BuildContext context,
    required Rect anchorRect,
    required List<BrowserContextMenuItem> items,
  }) async {
    final overlayRenderObject = Overlay.of(context).context.findRenderObject();
    if (overlayRenderObject is! RenderBox) return null;

    final theme = Theme.of(context);
    final popupItems = _buildPopupEntries(items, theme);
    if (popupItems.isEmpty) return null;

    return showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(
        anchorRect,
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
      items: popupItems,
    );
  }

  static List<PopupMenuEntry<Object>> _buildPopupEntries(
    List<BrowserContextMenuItem> items,
    ThemeData theme,
  ) {
    final popupEntries = <PopupMenuEntry<Object>>[];

    for (final item in items) {
      if (item.isSeparator) {
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

      if (item.isSubmenu) {
        popupEntries.addAll(_buildPopupEntries(item.children, theme));
        continue;
      }

      if (!item.isAction) continue;

      final isSelectable = item.enabled && item.value != null;

      popupEntries.add(
        PopupMenuItem<Object>(
          value: item.value,
          enabled: isSelectable,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: item.checkable && item.checked
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
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isSelectable
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
}

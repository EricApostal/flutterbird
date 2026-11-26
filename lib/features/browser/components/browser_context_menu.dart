import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';

enum BrowserContextMenuItemKind { action, separator, submenu }

class BrowserContextMenuItem {
  const BrowserContextMenuItem.action({
    required this.label,
    this.value,
    this.enabled = true,
    this.checkable = false,
    this.checked = false,
    this.shortcut = '',
  }) : kind = BrowserContextMenuItemKind.action,
       children = const [];

  const BrowserContextMenuItem.separator()
    : kind = BrowserContextMenuItemKind.separator,
      label = '',
      value = null,
      enabled = false,
      checkable = false,
      checked = false,
      shortcut = '',
      children = const [];

  const BrowserContextMenuItem.submenu({
    required this.label,
    required this.children,
  }) : kind = BrowserContextMenuItemKind.submenu,
       value = null,
       enabled = false,
       checkable = false,
       checked = false,
       shortcut = '';

  final BrowserContextMenuItemKind kind;
  final String label;
  final Object? value;
  final bool enabled;
  final bool checkable;
  final bool checked;

  /// The keys that do the same, shown on the desktop.
  final String shortcut;
  final List<BrowserContextMenuItem> children;

  bool get isAction => kind == BrowserContextMenuItemKind.action;
  bool get isSeparator => kind == BrowserContextMenuItemKind.separator;
  bool get isSubmenu => kind == BrowserContextMenuItemKind.submenu;
}

/// Shows the desktop's menu, with submenus. The phone has menus of its own.
class BrowserContextMenuPresenter {
  /// Opens under a button, or at the pointer, and returns what was chosen.
  static Future<Object?> show({
    required BuildContext context,
    required Rect anchorRect,
    required List<BrowserContextMenuItem> items,
  }) async {
    Object? chosen;
    List<BirdMenuEntry> entries(List<BrowserContextMenuItem> items) => [
      for (final item in items)
        if (item.isSeparator)
          const BirdMenuItem.separator()
        else if (item.isSubmenu)
          BirdMenuItem(item.label, submenu: entries(item.children))
        else
          BirdMenuItem(
            item.label,
            shortcut: item.shortcut,
            enabled: item.enabled && item.value != null,
            checked: item.checkable ? item.checked : null,
            onSelected: () => chosen = item.value,
          ),
    ];
    await showBirdMenu(
      context,
      anchorRect.bottomLeft,
      entries(items),
      alignRight: anchorRect.right,
    );
    return chosen;
  }
}

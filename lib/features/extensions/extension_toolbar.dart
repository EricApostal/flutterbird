import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';
import 'package:rubisco_browser/features/windows/window_system.dart';

/// What the toolbar's own buttons and the extensions menu share.

/// Does what pressing an extension's button does. Returns whether that is to
/// show its popup, which is the caller's to do; otherwise the extension has
/// been told of the press.
bool pressExtensionAction(
  WidgetRef ref,
  ExtensionService service,
  InstalledExtension extension,
) {
  final bridge = ref.read(browserBridgeProvider);
  final tabId = bridge?.activeTabId;
  final state = service.actions.stateFor(extension.uuid, tabId: tabId);
  if (!(state.enabled ?? true)) return false;
  if (state.popup?.isNotEmpty ?? false) return true;

  final tab = tabId == null ? null : bridge?.tab(tabId);
  ActionApi.notifyClicked(
    service.host,
    extension,
    tab?.toJson(includeIdentity: true) ?? {'id': tabId ?? -1},
  );
  return false;
}

/// Whether this widget's window is the one to answer something the whole app
/// heard, such as an extension asking for its popup. Every window has its own
/// toolbar, and one popup is wanted.
bool isToolbarOfKeyWindow(BuildContext context, WidgetRef ref) {
  final scope = context.getInheritedWidgetOfExactType<BrowserWindowScope>();
  if (scope == null) return true;
  return ref.read(windowSystemProvider).isKeyWindow(scope.windowId);
}

/// An extension's button icon, as it set it, with its badge.
class ExtensionActionIcon extends StatelessWidget {
  const ExtensionActionIcon({
    required this.service,
    required this.extension,
    required this.state,
    super.key,
  });

  final ExtensionService service;
  final InstalledExtension extension;
  final ActionState state;

  @override
  Widget build(BuildContext context) {
    const fallback = BirdIcon(BirdGlyph.extension, size: 17);
    final iconPath = state.iconPath;
    final badge = state.badgeText ?? '';
    final badgeColor = state.badgeBackground;
    final background = badgeColor == null
        ? null
        : Color.fromARGB(
            badgeColor[3],
            badgeColor[0],
            badgeColor[1],
            badgeColor[2],
          );

    return BirdBadge(
      label: badge,
      color: background,
      // Words an extension's own colour can be read under.
      textColor: background == null
          ? null
          : (background.computeLuminance() > 0.45
                ? const Color(0xFF000000)
                : const Color(0xFFFFFFFF)),
      child: Opacity(
        opacity: (state.enabled ?? true) ? 1 : 0.4,
        child: iconPath == null
            ? fallback
            : Image.file(
                File(
                  '${service.registry.directoryFor(extension).path}/$iconPath',
                ),
                width: 18,
                height: 18,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

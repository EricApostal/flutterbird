import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/windows/window_scope.dart';
import 'package:flutterbird/features/windows/window_system.dart';

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
    const fallback = Icon(Icons.extension_outlined, size: 20);
    final iconPath = state.iconPath;
    final badge = state.badgeText ?? '';
    final badgeColor = state.badgeBackground;

    return Badge(
      isLabelVisible: badge.isNotEmpty,
      label: Text(badge, style: const TextStyle(fontSize: 9)),
      backgroundColor: badgeColor == null
          ? null
          : Color.fromARGB(
              badgeColor[3],
              badgeColor[0],
              badgeColor[1],
              badgeColor[2],
            ),
      child: Opacity(
        opacity: (state.enabled ?? true) ? 1 : 0.4,
        child: iconPath == null
            ? fallback
            : Image.file(
                File(
                  '${service.registry.directoryFor(extension).path}/$iconPath',
                ),
                width: 20,
                height: 20,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// A panel hanging below the right end of a toolbar button, which a press
/// anywhere else dismisses.
class ToolbarDropdown extends StatelessWidget {
  const ToolbarDropdown({
    required this.link,
    required this.onDismiss,
    required this.child,
    super.key,
  });

  final LayerLink link;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onDismiss,
        child: CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 8),
          child: Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // swallow so it doesn't bubble to the barrier
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

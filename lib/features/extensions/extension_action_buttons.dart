import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/extensions/extension_popup.dart';
import 'package:flutterbird/features/extensions/extension_toolbar.dart';

/// The buttons of the extensions the user pinned to the toolbar. The others
/// are in the extensions menu.
class ExtensionActionButtons extends ConsumerWidget {
  const ExtensionActionButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(extensionActionsProvider).value ?? const [];
    final pinned = ref.watch(toolbarPinsProvider).value ?? const [];
    final byUuid = {for (final e in extensions) e.uuid: e};
    final shown = [for (final uuid in pinned) ?byUuid[uuid]];
    if (shown.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final extension in shown)
          _PinnedButton(key: ValueKey(extension.uuid), extension: extension),
      ],
    );
  }
}

class _PinnedButton extends ConsumerStatefulWidget {
  const _PinnedButton({required this.extension, super.key});

  final InstalledExtension extension;

  @override
  ConsumerState<_PinnedButton> createState() => _PinnedButtonState();
}

class _PinnedButtonState extends ConsumerState<_PinnedButton> {
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    unawaited(_listen());
  }

  /// The button changes when the extension changes it, and when the tab
  /// showing changes, since what it shows can be set per tab.
  Future<void> _listen() async {
    final service = await ref.read(extensionServiceProvider.future);
    if (!mounted) return;

    void refresh([Object? _]) {
      if (mounted) setState(() {});
    }

    _subscriptions.add(
      service.actions.changes
          .where((uuid) => uuid == widget.extension.uuid)
          .listen(refresh),
    );
    // An extension can open its own popup, as a password manager does when it
    // needs to be unlocked.
    _subscriptions.add(
      service.actions.popupRequests
          .where((uuid) => uuid == widget.extension.uuid)
          .listen((_) {
            if (!mounted || !isToolbarOfKeyWindow(context, ref)) return;
            final state = service.actions.stateFor(
              widget.extension.uuid,
              tabId: ref.read(browserBridgeProvider)?.activeTabId,
            );
            if (state.popup?.isNotEmpty ?? false) _overlay.show();
          }),
    );
    final bridge = ref.read(browserBridgeProvider);
    if (bridge != null) _subscriptions.add(bridge.tabEvents.listen(refresh));
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> _showMenu(ExtensionService service, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(at & Size.zero, Offset.zero & overlay.size),
      items: const [
        PopupMenuItem(value: 'unpin', child: Text('Unpin from toolbar')),
      ],
    );
    if (choice == 'unpin') {
      await service.pins.setPinned(widget.extension.uuid, pinned: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(extensionServiceProvider).value;
    if (service == null) return const SizedBox.shrink();

    final extension = widget.extension;
    final state = service.actions.stateFor(
      extension.uuid,
      tabId: ref.read(browserBridgeProvider)?.activeTabId,
    );
    final enabled = state.enabled ?? true;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) => ToolbarDropdown(
          link: _link,
          onDismiss: _overlay.hide,
          child: ExtensionPopup(
            url: '${extension.origin}/${state.popup}',
            contentSizes: service.host.contentSizes,
            onClose: _overlay.hide,
          ),
        ),
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              unawaited(_showMenu(service, details.globalPosition)),
          child: IconButton(
            tooltip: state.title ?? extension.name,
            onPressed: enabled
                ? () {
                    if (_overlay.isShowing) {
                      _overlay.hide();
                    } else if (pressExtensionAction(ref, service, extension)) {
                      _overlay.show();
                    }
                  }
                : null,
            icon: ExtensionActionIcon(
              service: service,
              extension: extension,
              state: state,
            ),
          ),
        ),
      ),
    );
  }
}

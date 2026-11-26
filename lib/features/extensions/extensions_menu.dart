import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:rubisco_browser/features/extensions/extension_toolbar.dart';

/// Every extension that has a button: press one to use it, or pin it to the
/// toolbar.
class ExtensionsMenu extends ConsumerWidget {
  const ExtensionsMenu({
    required this.onOpenPopup,
    required this.onManage,
    required this.onClose,
    super.key,
  });

  final void Function(InstalledExtension extension) onOpenPopup;
  final VoidCallback onManage;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = ref.watch(extensionServiceProvider).value;
    final extensions = ref.watch(extensionActionsProvider).value ?? const [];
    final pinned = ref.watch(toolbarPinsProvider).value ?? const [];
    final tabId = ref.read(browserBridgeProvider)?.activeTabId;

    return Material(
      elevation: 8,
      color: omniboxSurfaceColor(theme),
      borderRadius: BorderRadius.circular(kOmniboxFieldRadius),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Text('Extensions', style: theme.textTheme.titleSmall),
            ),
            if (service == null || extensions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                child: Text(
                  'No extensions with a button are turned on.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final extension in extensions)
                      _row(
                        context,
                        ref,
                        service,
                        extension,
                        tabId: tabId,
                        isPinned: pinned.contains(extension.uuid),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.settings_outlined, size: 20),
              title: const Text('Manage extensions'),
              onTap: onManage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    ExtensionService service,
    InstalledExtension extension, {
    required int? tabId,
    required bool isPinned,
  }) {
    final state = service.actions.stateFor(extension.uuid, tabId: tabId);

    return ListTile(
      dense: true,
      enabled: state.enabled ?? true,
      leading: ExtensionActionIcon(
        service: service,
        extension: extension,
        state: state,
      ),
      title: Text(extension.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(
        tooltip: isPinned ? 'Unpin from toolbar' : 'Pin to toolbar',
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
        onPressed: () => unawaited(
          service.pins.setPinned(extension.uuid, pinned: !isPinned),
        ),
      ),
      onTap: () {
        if (pressExtensionAction(ref, service, extension)) {
          onOpenPopup(extension);
        } else {
          onClose();
        }
      },
    );
  }
}

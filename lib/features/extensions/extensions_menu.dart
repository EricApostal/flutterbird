import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final service = ref.watch(extensionServiceProvider).value;
    final extensions = ref.watch(extensionActionsProvider).value ?? const [];
    final pinned = ref.watch(toolbarPinsProvider).value ?? const [];
    final tabId = ref.read(browserBridgeProvider)?.activeTabId;

    return BirdPanel(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BirdPanelHeader('Extensions'),
          if (service == null || extensions.isEmpty)
            const BirdPlaceholder(
              'No extensions with a button are turned on.',
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
            )
          else
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
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
            ),
          const BirdSeparator(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: BirdListRow(
              leading: const BirdIcon(BirdGlyph.gear),
              title: 'Manage extensions',
              onPressed: onManage,
            ),
          ),
        ],
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

    return BirdListRow(
      enabled: state.enabled ?? true,
      leading: ExtensionActionIcon(
        service: service,
        extension: extension,
        state: state,
      ),
      title: extension.name,
      trailing: BirdToolbarButton(
        glyph: isPinned ? BirdGlyph.pinFilled : BirdGlyph.pin,
        tooltip: isPinned ? 'Unpin from toolbar' : 'Pin to toolbar',
        size: 28,
        iconSize: 14,
        color: isPinned ? context.bird.link : null,
        onPressed: () => unawaited(
          service.pins.setPinned(extension.uuid, pinned: !isPinned),
        ),
      ),
      onPressed: () {
        if (pressExtensionAction(ref, service, extension)) {
          onOpenPopup(extension);
        } else {
          onClose();
        }
      },
    );
  }
}

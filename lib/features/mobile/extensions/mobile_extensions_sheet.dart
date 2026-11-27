import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/extensions/extension_toolbar.dart';
import 'package:rubisco_browser/features/mobile/extensions/mobile_extension_icon.dart';
import 'package:rubisco_browser/features/mobile/extensions/mobile_extension_popup.dart';
import 'package:rubisco_browser/features/mobile/extensions/mobile_extensions_page.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';

/// What was chosen from the sheet: an extension whose popup is wanted, or the
/// page that manages them.
sealed class _Choice {}

class _Popup extends _Choice {
  _Popup(this.service, this.extension);

  final ExtensionService service;
  final InstalledExtension extension;
}

class _Manage extends _Choice {}

/// The extensions that have a button, from the browser's menu: pressing one
/// does what its toolbar button would.
Future<void> showMobileExtensionsSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final choice = await showMobileSheet<_Choice>(
    context: context,
    builder: (context) => const _ExtensionsList(),
  );
  if (choice == null || !context.mounted) return;

  switch (choice) {
    case _Popup(:final service, :final extension):
      await showMobileExtensionPopup(
        context,
        service: service,
        bridge: container.read(browserBridgeProvider),
        extension: extension,
      );
    case _Manage():
      await pushMobilePage<void>(context, const MobileExtensionsPage());
  }
}

class _ExtensionsList extends ConsumerWidget {
  const _ExtensionsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(extensionServiceProvider).value;
    final extensions = ref.watch(extensionActionsProvider).value ?? const [];
    final tabId = ref.read(browserBridgeProvider)?.activeTabId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (service == null || extensions.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: Text(
              service == null
                  ? 'Extensions are still starting.'
                  : 'No extensions with a button are turned on.',
              style: TextStyle(color: context.mobile.textSecondary),
            ),
          )
        else
          for (final extension in extensions)
            _row(context, ref, service, extension, tabId),
        const Divider(),
        MobileMenuRow(
          icon: Icons.settings_outlined,
          label: 'Manage extensions',
          onTap: () => Navigator.of(context).pop(_Manage()),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    ExtensionService service,
    InstalledExtension extension,
    int? tabId,
  ) {
    final state = service.actions.stateFor(extension.uuid, tabId: tabId);
    final enabled = state.enabled ?? true;
    return ListTile(
      enabled: enabled,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: MobileExtensionIcon(
        service: service,
        extension: extension,
        state: state,
      ),
      title: Text(extension.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        final opensPopup = pressExtensionAction(ref, service, extension);
        Navigator.of(
          context,
        ).pop(opensPopup ? _Popup(service, extension) : null);
      },
    );
  }
}

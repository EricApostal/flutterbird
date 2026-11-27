import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/extensions/extension_toolbar.dart';
import 'package:rubisco_browser/features/mobile/extensions/mobile_extension_icon.dart';
import 'package:rubisco_browser/features/mobile/extensions/mobile_extension_install.dart';
import 'package:rubisco_browser/features/mobile/extensions/mobile_extension_popup.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/settings/settings_widgets.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';

const String _addonsForAndroid = 'https://addons.mozilla.org/android/';

/// Adding extensions, and managing those there are.
class MobileExtensionsPage extends ConsumerStatefulWidget {
  const MobileExtensionsPage({super.key});

  @override
  ConsumerState<MobileExtensionsPage> createState() =>
      _MobileExtensionsPageState();
}

class _MobileExtensionsPageState extends ConsumerState<MobileExtensionsPage> {
  final TextEditingController _input = TextEditingController();
  bool _busy = false;
  ExtensionOutcome? _outcome;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Runs [action], showing how it went rather than letting it throw.
  Future<void> _run(
    Future<ExtensionOutcome?> Function(ExtensionService) action,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _outcome = null;
    });
    ExtensionOutcome? outcome;
    try {
      outcome = await action(await ref.read(extensionServiceProvider.future));
    } on InstallCancelled {
      outcome = null;
    } on Object catch (error) {
      outcome = (message: describeExtensionError(error), failed: true);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
    });
  }

  Future<void> _add() async {
    final input = _input.text.trim();
    if (input.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await _run((service) async {
      final outcome = await addExtension(context, service, input);
      if (outcome != null && !outcome.failed && mounted) _input.clear();
      return outcome;
    });
  }

  Future<void> _updateAll() => _run((service) async {
    final count = await service.updateAll(
      onPrompt: (prompt) async =>
          mounted && await showMobileInstallPrompt(context, prompt),
    );
    return (
      message: count == 0
          ? 'Everything is up to date'
          : 'Updated $count extension${count == 1 ? '' : 's'}',
      failed: false,
    );
  });

  Future<void> _showDetails(InstalledExtension extension) async {
    final service = await ref.read(extensionServiceProvider.future);
    final manifest = await service.host.manifestOf(extension);
    if (!mounted) return;

    final bridge = ref.read(browserBridgeProvider);
    final hasButton = extension.enabled && manifest?.action != null;
    final options = extension.enabled ? manifest?.options : null;

    final choice = await showMobileSheet<String>(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18),
            leading: MobileExtensionIcon(
              service: service,
              extension: extension,
              size: 32,
            ),
            title: Text(extension.name),
            subtitle: Text('Version ${extension.version}'),
          ),
          if (extension.description case final description?
              when description.isNotEmpty && !description.startsWith('__MSG_'))
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(
                description,
                style: TextStyle(color: context.mobile.textSecondary),
              ),
            ),
          const Divider(),
          if (hasButton)
            MobileMenuRow(
              icon: Icons.open_in_browser_rounded,
              label: 'Open',
              onTap: () => Navigator.of(context).pop('open'),
            ),
          if (options != null)
            MobileMenuRow(
              icon: Icons.tune_rounded,
              label: 'Extension settings',
              onTap: () => Navigator.of(context).pop('options'),
            ),
          MobileMenuRow(
            icon: Icons.delete_outline_rounded,
            label: 'Remove',
            onTap: () => Navigator.of(context).pop('remove'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'open':
        if (pressExtensionAction(ref, service, extension)) {
          await showMobileExtensionPopup(
            context,
            service: service,
            bridge: bridge,
            extension: extension,
          );
        } else {
          // It has no popup, so what it does is done to the page.
          closeMobileOverlays(Navigator.of(context, rootNavigator: true));
        }
      case 'options':
        final page = options!.page;
        openInNewTab(
          context,
          '${extension.origin}/${page.startsWith('/') ? page.substring(1) : page}',
        );
      case 'remove':
        final agreed = await confirmMobileAction(
          context: context,
          title: 'Remove ${extension.name}?',
          message: 'The extension and what it saved are deleted.',
          confirm: 'Remove',
        );
        if (agreed) {
          await _run((service) async {
            await service.uninstall(extension.id);
            return (message: 'Removed ${extension.name}', failed: false);
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final extensions = ref.watch(installedExtensionsProvider);
    final service = ref.watch(extensionServiceProvider).value;

    return SettingsScreen(
      title: 'Extensions',
      children: [
        SettingsGroup(
          title: 'Add an extension',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _add(),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Add-on link or name',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _add,
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
            SettingsRow(
              icon: Icons.travel_explore_rounded,
              title: 'Find add-ons',
              subtitle:
                  'On an add-on’s page, open the menu and choose '
                  '“Add extension”.',
              onTap: () => openInNewTab(context, _addonsForAndroid),
            ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 18),
            child: LinearProgressIndicator(),
          ),
        if (_outcome case final outcome?)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
            child: Text(
              outcome.message,
              style: TextStyle(
                color: outcome.failed ? colors.danger : colors.text,
              ),
            ),
          ),
        extensions.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator.adaptive(),
            ),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Extensions are unavailable: $error',
              style: TextStyle(color: colors.danger),
            ),
          ),
          data: (list) => list.isEmpty || service == null
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    'No extensions yet',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                )
              : SettingsGroup(
                  title: 'Installed',
                  children: [
                    for (final extension in list)
                      SettingsRow(
                        key: ValueKey(extension.uuid),
                        leading: MobileExtensionIcon(
                          service: service,
                          extension: extension,
                        ),
                        title: extension.name,
                        subtitle: extension.version,
                        onTap: () => _showDetails(extension),
                        trailing: Switch(
                          value: extension.enabled,
                          onChanged: _busy
                              ? null
                              : (enabled) => _run((service) async {
                                  await service.setEnabled(
                                    extension.id,
                                    enabled: enabled,
                                  );
                                  return null;
                                }),
                        ),
                      ),
                    SettingsRow(
                      icon: Icons.update_rounded,
                      title: 'Check for updates',
                      onTap: _busy ? null : _updateAll,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

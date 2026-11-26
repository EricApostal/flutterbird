import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:rubisco_browser/features/extensions/install_prompt_dialog.dart';

/// The list of installed extensions, with where to add more.
class ExtensionsPanel extends ConsumerStatefulWidget {
  const ExtensionsPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<ExtensionsPanel> createState() => _ExtensionsPanelState();
}

class _ExtensionsPanelState extends ConsumerState<ExtensionsPanel> {
  final TextEditingController _amoController = TextEditingController();
  final TextEditingController _folderController = TextEditingController();

  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  // Desktop only: a folder path has no meaning on Android.
  static final bool _canLoadUnpacked =
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  void dispose() {
    _amoController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  Future<bool> _confirm(InstallPrompt prompt) async {
    if (!mounted) return false;
    return showInstallPrompt(context, prompt);
  }

  /// Runs [action], showing what it reports instead of letting it throw.
  Future<void> _run(Future<String?> Function(ExtensionService) action) async {
    setState(() {
      _busy = true;
      _message = null;
    });

    String? message;
    var isError = false;
    try {
      final service = await ref.read(extensionServiceProvider.future);
      message = await action(service);
    } on InstallCancelled {
      message = null;
    } on AmoInputException catch (error) {
      message = error.message;
      isError = true;
    } on AmoException catch (error) {
      message = error.message;
      isError = true;
    } on InstallException catch (error) {
      message = error.message;
      isError = true;
    } on FetchException catch (error) {
      message = error.message;
      isError = true;
    } on Object catch (error) {
      message = '$error';
      isError = true;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _installFromAmo() async {
    final input = _amoController.text.trim();
    if (input.isEmpty) return;

    await _run((service) async {
      final result = await service.installFromAmo(input, onPrompt: _confirm);
      _amoController.clear();
      return 'Added ${result.extension.name}';
    });
  }

  Future<void> _loadUnpacked() async {
    final path = _folderController.text.trim();
    if (path.isEmpty) return;

    await _run((service) async {
      final result = await service.loadUnpacked(path, onPrompt: _confirm);
      _folderController.clear();
      return '${result.wasUpdate ? 'Reloaded' : 'Loaded'} ${result.extension.name}';
    });
  }

  Future<void> _updateAll() async {
    await _run((service) async {
      final count = await service.updateAll(onPrompt: _confirm);
      return count == 0
          ? 'Everything is up to date'
          : 'Updated $count extension${count == 1 ? '' : 's'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extensions = ref.watch(installedExtensionsProvider);

    return Material(
      elevation: 6,
      color: omniboxSurfaceColor(theme),
      borderRadius: BorderRadius.circular(kOmniboxFieldRadius),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Extensions',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.system_update_alt, size: 18),
                    tooltip: 'Check for updates',
                    onPressed: _busy ? null : _updateAll,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Close',
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outline.withAlpha(50)),
            Flexible(
              child: extensions.when(
                data: (list) => _InstalledList(extensions: list, busy: _busy),
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Extensions are unavailable: $error'),
                ),
              ),
            ),
            Divider(height: 1, color: theme.colorScheme.outline.withAlpha(50)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InputRow(
                    controller: _amoController,
                    hint: 'addons.mozilla.org link or name',
                    action: 'Add',
                    busy: _busy,
                    onSubmit: _installFromAmo,
                  ),
                  if (_canLoadUnpacked) ...[
                    const SizedBox(height: 8),
                    _InputRow(
                      controller: _folderController,
                      hint: 'Folder of an unpacked extension',
                      action: 'Load',
                      busy: _busy,
                      onSubmit: _loadUnpacked,
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _message!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _messageIsError
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.hint,
    required this.action,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String hint;
  final String action;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !busy,
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: busy ? null : onSubmit, child: Text(action)),
      ],
    );
  }
}

class _InstalledList extends ConsumerWidget {
  const _InstalledList({required this.extensions, required this.busy});

  final List<InstalledExtension> extensions;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (extensions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'No extensions yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: extensions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final extension = extensions[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.extension_outlined),
          title: Text(extension.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(extension.version, style: theme.textTheme.bodySmall),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: extension.enabled,
                onChanged: busy
                    ? null
                    : (enabled) async {
                        final service = await ref.read(
                          extensionServiceProvider.future,
                        );
                        await service.setEnabled(
                          extension.id,
                          enabled: enabled,
                        );
                      },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: 'Remove',
                onPressed: busy
                    ? null
                    : () async {
                        final service = await ref.read(
                          extensionServiceProvider.future,
                        );
                        await service.uninstall(extension.id);
                      },
              ),
            ],
          ),
        );
      },
    );
  }
}

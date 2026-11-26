import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final extensions = ref.watch(installedExtensionsProvider);

    return BirdPanel(
      width: 400,
      constraints: const BoxConstraints(maxHeight: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BirdPanelHeader(
            'Extensions',
            actions: [
              BirdToolbarButton(
                glyph: BirdGlyph.update,
                tooltip: 'Check for updates',
                size: 28,
                iconSize: 14,
                onPressed: _busy ? null : _updateAll,
              ),
            ],
            onClose: widget.onClose,
          ),
          Flexible(
            child: extensions.when(
              data: (list) => _InstalledList(extensions: list, busy: _busy),
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: BirdSpinner(size: 22)),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: BirdMessageBar(
                  'Extensions are unavailable: $error',
                  kind: BirdMessageKind.error,
                ),
              ),
            ),
          ),
          const BirdSeparator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 10),
                  const BirdProgressBar(),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 10),
                  BirdMessageBar(
                    _message!,
                    kind: _messageIsError
                        ? BirdMessageKind.error
                        : BirdMessageKind.success,
                  ),
                ],
              ],
            ),
          ),
        ],
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
          child: BirdTextField(
            controller: controller,
            enabled: !busy,
            placeholder: hint,
            semanticLabel: hint,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(width: 6),
        BirdButton(action, onPressed: busy ? null : onSubmit),
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
    if (extensions.isEmpty) {
      return const BirdPlaceholder('No extensions yet');
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: extensions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final extension = extensions[index];
        return BirdListRow(
          leading: const BirdIcon(BirdGlyph.extension),
          title: extension.name,
          subtitle: extension.version,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BirdSwitch(
                value: extension.enabled,
                semanticLabel: 'Enable ${extension.name}',
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
              const SizedBox(width: 6),
              BirdToolbarButton(
                glyph: BirdGlyph.trash,
                tooltip: 'Remove',
                size: 28,
                iconSize: 14,
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

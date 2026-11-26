import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/settings/settings_widgets.dart';
import 'package:rubisco_browser/features/settings/settings_controller.dart';

/// Which engine searches, and the user's own engines.
class SearchSettingsPage extends ConsumerWidget {
  const SearchSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final engines = ref.watch(searchEnginesProvider);
    final chosen =
        settings.searchEngineName ??
        LadybirdController.fallbackSearchEngine.name;
    final custom = {
      for (final engine in settings.customSearchEngines) engine.name,
    };

    void remove(String name) {
      if (!LadybirdController.removeCustomSearchEngine(name)) {
        debugPrint('The engine refused to remove the search engine $name.');
        return;
      }
      ref.read(settingsProvider.notifier).reload();
    }

    return SettingsScreen(
      title: 'Search engine',
      children: [
        if (engines.isNotEmpty)
          SettingsGroup(
            title: 'Search from the address bar with',
            children: [
              for (final engine in engines)
                SettingsChoiceRow(
                  title: engine.name,
                  subtitle:
                      Uri.tryParse(engine.queryUrl)?.host ?? engine.queryUrl,
                  selected: engine.name == chosen,
                  onTap: () => ref.read(settingsProvider.notifier).apply({
                    'searchEngine': {'engine': engine.name},
                  }),
                  trailing: custom.contains(engine.name)
                      ? IconButton(
                          tooltip: 'Remove ${engine.name}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => remove(engine.name),
                        )
                      : null,
                ),
            ],
          ),
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.add,
              title: 'Add a search engine',
              onTap: () async {
                final added = await showDialog<bool>(
                  context: context,
                  builder: (context) => const _AddEngineDialog(),
                );
                if (added == true && context.mounted) {
                  ref.read(settingsProvider.notifier).reload();
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _AddEngineDialog extends StatefulWidget {
  const _AddEngineDialog();

  @override
  State<_AddEngineDialog> createState() => _AddEngineDialogState();
}

class _AddEngineDialogState extends State<_AddEngineDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _url = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _add() {
    try {
      LadybirdController.addNewSearchEngine(_name.text, _url.text);
    } on ArgumentError catch (error) {
      setState(() => _error = error.message?.toString());
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a search engine'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Search URL',
              hintText: 'https://example.com/search?q=%s',
              helperText: '%s is where the search text goes',
              errorText: _error,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _add, child: const Text('Add')),
      ],
    );
  }
}

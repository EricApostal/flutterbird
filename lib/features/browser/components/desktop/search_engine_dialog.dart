import 'package:flutter/material.dart';

// Prompts for a custom search engine's name and query-URL template.
//
// [onSubmit] performs the add itself and returns an error message to display,
// or null once the engine accepted the pair. The dialog stays open on an error,
// so the user sees exactly what was rejected instead of the dialog closing as
// if it had worked.
//
// Resolves to true when an engine was added, false when the user cancelled.
Future<bool> showAddSearchEngineDialog({
  required BuildContext context,
  required String? Function(String name, String queryUrl) onSubmit,
}) async {
  final added = await showDialog<bool>(
    context: context,
    builder: (context) => AddSearchEngineDialog(onSubmit: onSubmit),
  );
  return added ?? false;
}

class AddSearchEngineDialog extends StatefulWidget {
  const AddSearchEngineDialog({required this.onSubmit, super.key});

  final String? Function(String name, String queryUrl) onSubmit;

  @override
  State<AddSearchEngineDialog> createState() => _AddSearchEngineDialogState();
}

class _AddSearchEngineDialogState extends State<AddSearchEngineDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _queryUrlController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _queryUrlController.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.onSubmit(
      _nameController.text,
      _queryUrlController.text,
    );
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add search engine'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Mojeek (work)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queryUrlController,
            decoration: const InputDecoration(
              labelText: 'Search URL',
              hintText: 'https://example.com/search?q=%s',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
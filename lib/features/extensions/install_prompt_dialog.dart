import 'package:bird_extensions/bird_extensions.dart';
import 'package:flutter/material.dart';

/// Asks the user whether to add or update an extension, showing what it asks
/// for. Returns true when they approve.
Future<bool> showInstallPrompt(
  BuildContext context,
  InstallPrompt prompt,
) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (context) => _InstallPromptDialog(prompt: prompt),
  );
  return approved ?? false;
}

class _InstallPromptDialog extends StatelessWidget {
  const _InstallPromptDialog({required this.prompt});

  final InstallPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions = prompt.permissions;

    return AlertDialog(
      title: Text('${prompt.isUpdate ? 'Update' : 'Add'} ${prompt.name}?'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (prompt.description != null &&
                  prompt.description!.isNotEmpty) ...[
                Text(prompt.description!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              if (permissions.isEmpty)
                Text(
                  prompt.isUpdate
                      ? 'This update asks for nothing new.'
                      : 'It does not ask for any special permissions.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                Text(
                  prompt.isUpdate ? 'New permissions:' : 'It asks to:',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                for (final line in permissions.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(line)),
                      ],
                    ),
                  ),
              ],
              for (final line in permissions.dataCollectionLines) ...[
                const SizedBox(height: 8),
                Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Only add extensions from developers you trust.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(prompt.isUpdate ? 'Update' : 'Add'),
        ),
      ],
    );
  }
}

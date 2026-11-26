import 'package:bird_extensions/bird_extensions.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';

/// Asks the user whether to add or update an extension, showing what it asks
/// for. Returns true when they approve.
Future<bool> showInstallPrompt(
  BuildContext context,
  InstallPrompt prompt,
) async {
  final approved = await showBirdDialog<bool>(
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
    final permissions = prompt.permissions;
    final body = context.birdText(height: 1.4);
    final quiet = context.birdText(
      color: context.bird.textSecondary,
      size: BirdTextSize.small,
    );

    return BirdDialog(
      leading: const BirdIcon(BirdGlyph.extension, size: 20),
      title: '${prompt.isUpdate ? 'Update' : 'Add'} ${prompt.name}?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (prompt.description != null && prompt.description!.isNotEmpty) ...[
            Text(prompt.description!, style: body),
            const SizedBox(height: 12),
          ],
          if (permissions.isEmpty)
            Text(
              prompt.isUpdate
                  ? 'This update asks for nothing new.'
                  : 'It does not ask for any special permissions.',
              style: body,
            )
          else ...[
            Text(
              prompt.isUpdate ? 'New permissions:' : 'It asks to:',
              style: context.birdText(weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final line in permissions.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: body),
                    Expanded(child: Text(line, style: body)),
                  ],
                ),
              ),
          ],
          for (final line in permissions.dataCollectionLines) ...[
            const SizedBox(height: 8),
            Text(line, style: quiet),
          ],
          const SizedBox(height: 12),
          Text('Only add extensions from developers you trust.', style: quiet),
        ],
      ),
      // No default: a key already on its way must not add anything.
      actions: [
        BirdDialogAction(
          'Cancel',
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BirdDialogAction(
          prompt.isUpdate ? 'Update' : 'Add',
          kind: BirdButtonKind.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

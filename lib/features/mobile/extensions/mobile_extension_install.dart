import 'package:bird_core/bird_core.dart';
import 'package:bird_extensions/bird_extensions.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

/// How adding an extension went, to be told to the user.
typedef ExtensionOutcome = ({String message, bool failed});

/// Whether [url] is the page of one add-on on addons.mozilla.org, which can be
/// added from where it is.
bool isAddonPage(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != 'addons.mozilla.org') return false;
  final segments = uri.pathSegments;
  final addon = segments.indexOf('addon');
  return addon >= 0 &&
      addon + 1 < segments.length &&
      segments[addon + 1].isNotEmpty;
}

String describeExtensionError(Object error) => switch (error) {
  AmoInputException(:final message) => message,
  AmoException(:final message) => message,
  InstallException(:final message) => message,
  FetchException(:final message) => message,
  _ => '$error',
};

/// Adds the add-on [input] names, a link or a name, once the user agrees to
/// what it asks for. Returns null where they do not.
Future<ExtensionOutcome?> addExtension(
  BuildContext context,
  ExtensionService service,
  String input,
) async {
  try {
    final result = await service.installFromAmo(
      input,
      onPrompt: (prompt) async =>
          context.mounted && await showMobileInstallPrompt(context, prompt),
    );
    return (message: 'Added ${result.extension.name}', failed: false);
  } on InstallCancelled {
    return null;
  } on Object catch (error) {
    return (message: describeExtensionError(error), failed: true);
  }
}

/// Asks whether to add or update an extension, showing what it asks for.
Future<bool> showMobileInstallPrompt(
  BuildContext context,
  InstallPrompt prompt,
) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = context.mobile;
      final permissions = prompt.permissions;
      final body = TextStyle(fontSize: 14.5, height: 1.4, color: colors.text);
      final quiet = TextStyle(
        fontSize: 13,
        height: 1.4,
        color: colors.textSecondary,
      );
      final description = prompt.description ?? '';

      return AlertDialog(
        icon: const Icon(Icons.extension_rounded),
        title: Text('${prompt.isUpdate ? 'Update' : 'Add'} ${prompt.name}?'),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (description.isNotEmpty) ...[
              Text(description, style: body),
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
                style: body.copyWith(fontWeight: FontWeight.w600),
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
            Text(
              'Only add extensions from developers you trust.',
              style: quiet,
            ),
          ],
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
    },
  );
  return approved ?? false;
}

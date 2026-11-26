import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';

/// What can be done with an address in one of the browser's lists.
Future<void> showLinkMenu(
  BuildContext context,
  String url, {

  /// Where to open the menu from.
  required BuildContext anchor,
  required String removeLabel,
  required VoidCallback onRemove,
}) async {
  final choice = await showMobileMenu<String>(
    context: context,
    anchor: globalRectOf(anchor),
    width: 240,
    builder: (context) {
      Widget row(IconData icon, String label, String value) => MobileMenuRow(
        icon: icon,
        label: label,
        onTap: () => Navigator.of(context).pop(value),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(Icons.add_box_outlined, 'Open in new tab', 'tab'),
          row(Icons.link_rounded, 'Copy link', 'copy'),
          row(Icons.share_outlined, 'Share link', 'share'),
          row(Icons.delete_outline, removeLabel, 'remove'),
        ],
      );
    },
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'tab':
      openInNewTab(context, url);
    case 'copy':
      await copyText(context, url);
    case 'share':
      await shareText(context, url);
    case 'remove':
      onRemove();
  }
}

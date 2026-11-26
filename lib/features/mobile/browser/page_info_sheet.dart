import 'package:bird_session/bird_session.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';

/// What there is to say about the page on screen.
///
/// The engine does not yet report how a load went or show a certificate, so
/// this goes by the address alone, and never calls a page safe.
Future<void> showPageInfoSheet(BuildContext context, LadybirdController tab) {
  final url = tab.urlNotifier.value;
  final security = SiteSecurity.of(url);

  final (icon, heading, detail) = switch (security.kind) {
    SiteSecurityKind.https => (
      Icons.lock_outline,
      'Loaded over HTTPS',
      'What you send is encrypted on the way. This browser cannot show the '
          "site's certificate yet.",
    ),
    SiteSecurityKind.insecure => (
      Icons.warning_amber_rounded,
      'Connection is not secure',
      'Others on the network could read or change what you send. Don\'t enter '
          'passwords or card numbers here.',
    ),
    SiteSecurityKind.local => (
      Icons.computer,
      'On this device',
      'This page did not cross a network.',
    ),
    SiteSecurityKind.file => (
      Icons.description_outlined,
      'A file on this device',
      'This page did not cross a network.',
    ),
    SiteSecurityKind.extension => (
      Icons.extension_outlined,
      'An extension\'s page',
      'It belongs to an extension you added.',
    ),
    SiteSecurityKind.internal => (
      Icons.info_outline,
      'A page of Rubisco',
      'It is part of the browser.',
    ),
  };

  return showMobileSheet<void>(
    context: context,
    builder: (context) {
      final colors = context.mobile;
      final insecure = security.kind == SiteSecurityKind.insecure;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: TabIcon(tab: tab, size: 28),
              title: Text(
                security.host.isEmpty ? tabTitle(tab) : security.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18),
              ),
              subtitle: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const Divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 4,
              ),
              leading: Icon(
                icon,
                color: insecure ? colors.danger : colors.textSecondary,
              ),
              title: Text(
                heading,
                style: TextStyle(color: insecure ? colors.danger : null),
              ),
              subtitle: Text(detail),
            ),
            const Divider(),
            MobileMenuRow(
              icon: Icons.copy_rounded,
              label: 'Copy link',
              onTap: () {
                Navigator.of(context).pop();
                copyText(context, url);
              },
            ),
            MobileMenuRow(
              icon: Icons.share_outlined,
              label: 'Share…',
              onTap: () {
                Navigator.of(context).pop();
                shareText(context, url);
              },
            ),
          ],
        ),
      );
    },
  );
}

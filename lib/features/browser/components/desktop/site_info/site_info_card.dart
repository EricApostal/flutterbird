import 'package:bird_session/bird_session.dart';
import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/site_info/permission_kinds.dart';
import 'package:flutterbird/features/browser/components/desktop/site_info/site_card.dart';
import 'package:ladybird/ladybird.dart';

/// What is known about the site a tab shows, and what it may do.
class SiteInfoCard extends StatelessWidget {
  const SiteInfoCard({required this.tab, super.key});

  final LadybirdController tab;

  static (IconData, String, String?) _connection(SiteSecurityKind kind) =>
      switch (kind) {
        SiteSecurityKind.https => (
          Icons.lock_outline,
          'This address uses HTTPS',
          'Secure connection',
        ),
        SiteSecurityKind.insecure => (
          Icons.no_encryption_outlined,
          'Connection is not secure',
          'Others on the network can read or change what you send here. Do '
              'not enter passwords or card numbers.',
        ),
        SiteSecurityKind.local => (
          Icons.computer,
          'Served by this computer',
          null,
        ),
        SiteSecurityKind.file => (
          Icons.insert_drive_file_outlined,
          'A file on this computer',
          null,
        ),
        SiteSecurityKind.extension => (
          Icons.extension_outlined,
          'A page of an extension',
          null,
        ),
        SiteSecurityKind.internal => (Icons.public, 'A browser page', null),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        tab.urlNotifier,
        LadybirdSiteBridge.instance,
      ]),
      builder: (context, _) {
        final security = SiteSecurity.of(tab.urlNotifier.value);
        final (icon, title, detail) = _connection(security.kind);
        final site = LadybirdSiteBridge.instance.sitePermissions(tab.viewId);
        final isWeb = switch (security.kind) {
          SiteSecurityKind.https ||
          SiteSecurityKind.insecure ||
          SiteSecurityKind.local => true,
          _ => false,
        };

        return SiteCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (security.host.isNotEmpty && isWeb) ...[
                Text(
                  security.host,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const Divider(height: 20),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: security.kind == SiteSecurityKind.insecure
                        ? theme.colorScheme.error
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.bodyMedium),
                        if (detail != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              detail,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isWeb && site != null && !site.isOpaque) ...[
                const Divider(height: 22),
                Text('Permissions', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final permission in site.permissions)
                  _PermissionRow(
                    viewId: tab.viewId,
                    origin: site.origin,
                    permission: permission,
                  ),
                if (site.permissions.any(
                  (p) => p.setting != PermissionSetting.ask,
                ))
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => LadybirdSiteBridge.instance
                          .resetSitePermissions(tab.viewId, site.origin),
                      child: const Text('Reset permissions'),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.viewId,
    required this.origin,
    required this.permission,
  });

  final int viewId;
  final String origin;
  final SitePermission permission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = PermissionKind.of(permission.name);
    final once = permission.setting == PermissionSetting.allowOnce;

    return Row(
      children: [
        Icon(kind.icon, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            permission.requestedByPage &&
                    permission.setting == PermissionSetting.ask
                ? '${kind.label} (requested)'
                : kind.label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        DropdownButton<PermissionSetting>(
          value: permission.setting,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: theme.textTheme.bodySmall,
          items: [
            const DropdownMenuItem(
              value: PermissionSetting.ask,
              child: Text('Ask'),
            ),
            const DropdownMenuItem(
              value: PermissionSetting.allow,
              child: Text('Allow'),
            ),
            if (once)
              const DropdownMenuItem(
                value: PermissionSetting.allowOnce,
                child: Text('Allowed for now'),
              ),
            const DropdownMenuItem(
              value: PermissionSetting.block,
              child: Text('Block'),
            ),
          ],
          onChanged: (setting) {
            if (setting == null || setting == permission.setting) return;
            LadybirdSiteBridge.instance.setSitePermission(
              viewId,
              origin,
              permission.name,
              setting,
            );
          },
        ),
      ],
    );
  }
}

import 'package:bird_session/bird_session.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/permission_kinds.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/site_card.dart';
import 'package:ladybird/ladybird.dart';

/// What is known about the site a tab shows, and what it may do.
class SiteInfoCard extends StatelessWidget {
  const SiteInfoCard({required this.tab, super.key});

  final LadybirdController tab;

  static (BirdGlyph, String, String?) _connection(SiteSecurityKind kind) =>
      switch (kind) {
        SiteSecurityKind.https => (
          BirdGlyph.lock,
          'This address uses HTTPS',
          'Secure connection',
        ),
        SiteSecurityKind.insecure => (
          BirdGlyph.lockOff,
          'Connection is not secure',
          'Others on the network can read or change what you send here. Do '
              'not enter passwords or card numbers.',
        ),
        SiteSecurityKind.local => (
          BirdGlyph.computer,
          'Served by this computer',
          null,
        ),
        SiteSecurityKind.file => (
          BirdGlyph.file,
          'A file on this computer',
          null,
        ),
        SiteSecurityKind.extension => (
          BirdGlyph.extension,
          'A page of an extension',
          null,
        ),
        SiteSecurityKind.internal => (BirdGlyph.globe, 'A browser page', null),
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;

    return ListenableBuilder(
      listenable: Listenable.merge([
        tab.urlNotifier,
        LadybirdSiteBridge.instance,
      ]),
      builder: (context, _) {
        final security = SiteSecurity.of(tab.urlNotifier.value);
        final (glyph, title, detail) = _connection(security.kind);
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
                  style: context.birdText(weight: FontWeight.w600),
                ),
                const BirdSeparator(space: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BirdIcon(
                    glyph,
                    size: 16,
                    color: security.kind == SiteSecurityKind.insecure
                        ? colors.danger
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.birdText()),
                        if (detail != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              detail,
                              style: context.birdText(
                                color: colors.textSecondary,
                                size: BirdTextSize.small,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isWeb && site != null && !site.isOpaque) ...[
                const BirdSeparator(space: 11),
                Text(
                  'Permissions',
                  style: context.birdText(weight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                for (final permission in site.permissions)
                  _PermissionRow(
                    viewId: tab.viewId,
                    origin: site.origin,
                    permission: permission,
                  ),
                if (site.permissions.any(
                  (p) => p.setting != PermissionSetting.ask,
                ))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: BirdButton(
                        'Reset permissions',
                        small: true,
                        onPressed: () => LadybirdSiteBridge.instance
                            .resetSitePermissions(tab.viewId, site.origin),
                      ),
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
    final kind = PermissionKind.of(permission.name);
    final once = permission.setting == PermissionSetting.allowOnce;

    return SizedBox(
      height: 30,
      child: Row(
        children: [
          BirdIcon(kind.glyph, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              permission.requestedByPage &&
                      permission.setting == PermissionSetting.ask
                  ? '${kind.label} (requested)'
                  : kind.label,
              style: context.birdText(),
            ),
          ),
          BirdSelect<PermissionSetting>(
            value: permission.setting,
            small: true,
            semanticLabel: kind.label,
            options: [
              const BirdOption(PermissionSetting.ask, 'Ask'),
              const BirdOption(PermissionSetting.allow, 'Allow'),
              if (once)
                const BirdOption(
                  PermissionSetting.allowOnce,
                  'Allowed for now',
                ),
              const BirdOption(PermissionSetting.block, 'Block'),
            ],
            onChanged: (setting) {
              LadybirdSiteBridge.instance.setSitePermission(
                viewId,
                origin,
                permission.name,
                setting,
              );
            },
          ),
        ],
      ),
    );
  }
}

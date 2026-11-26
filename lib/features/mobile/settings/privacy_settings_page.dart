import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/library/history_page.dart';
import 'package:rubisco_browser/features/mobile/settings/settings_widgets.dart';
import 'package:rubisco_browser/features/settings/settings_controller.dart';

/// What the browser shares and blocks, and what it remembers.
class PrivacySettingsPage extends ConsumerWidget {
  const PrivacySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    void apply(Map<String, Object?> changes) {
      if (ref.read(settingsProvider.notifier).apply(changes)) return;
      debugPrint('The engine refused a settings change: $changes');
    }

    return SettingsScreen(
      title: 'Privacy and security',
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.delete_outline,
              title: 'Delete browsing history',
              subtitle: 'The pages you have visited',
              onTap: () => confirmAndClearHistory(context),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Privacy',
          children: [
            SettingsSwitchRow(
              title: 'Content blocking',
              subtitle: 'Block ads, trackers and other unwanted requests',
              value: settings.contentBlockerEnabled,
              onChanged: (value) => apply({
                'contentBlockers': {'enabled': value},
              }),
            ),
            SettingsSwitchRow(
              title: 'Global Privacy Control',
              subtitle: 'Ask every site not to sell or share what you do on it',
              value: settings.globalPrivacyControl,
              onChanged: (value) => apply({'globalPrivacyControl': value}),
            ),
          ],
        ),
        SettingsGroup(
          title: 'In the background',
          children: [
            SettingsSwitchRow(
              title: 'Background networking',
              subtitle:
                  'Let the browser fetch things while you are not on a page, '
                  'such as newer filter lists',
              value: settings.backgroundNetworkingEnabled,
              onChanged: (value) => apply({
                'backgroundNetworking': {'enabled': value},
              }),
            ),
            SettingsSwitchRow(
              title: 'Update filter lists automatically',
              subtitle:
                  "Download newer versions of the content blocker's lists",
              value: settings.filterListUpdatesEnabled,
              onChanged: (value) => apply({
                'backgroundNetworking': {
                  'features': {'contentBlockerSubscriptionUpdates': value},
                },
              }),
            ),
          ],
        ),
      ],
    );
  }
}

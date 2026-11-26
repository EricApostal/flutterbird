import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/library/downloads_page.dart';
import 'package:rubisco_browser/features/mobile/settings/general_settings_pages.dart';
import 'package:rubisco_browser/features/mobile/settings/new_tab_settings_page.dart';
import 'package:rubisco_browser/features/mobile/settings/privacy_settings_page.dart';
import 'package:rubisco_browser/features/mobile/settings/search_settings_page.dart';
import 'package:rubisco_browser/features/mobile/settings/settings_widgets.dart';
import 'package:rubisco_browser/features/mobile/state/mobile_preferences.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/settings/settings_controller.dart';

/// The browser's settings on a phone.
///
/// Every value of the engine's comes from the engine and every change goes
/// back to it, through the same controller as the desktop's settings page.
class MobileSettingsPage extends ConsumerStatefulWidget {
  const MobileSettingsPage({super.key});

  @override
  ConsumerState<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends ConsumerState<MobileSettingsPage> {
  @override
  void initState() {
    super.initState();
    // The engine may have changed them since they were last read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(settingsProvider.notifier).reload();
    });
  }

  void _open(Widget page) => pushMobilePage<void>(context, page);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final addressBar = ref.watch(
      mobilePreferencesProvider.select((value) => value.addressBar),
    );

    if (!settings.isLoaded) {
      return SettingsScreen(
        title: 'Settings',
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.refresh,
                title: 'Try again',
                subtitle: 'The engine is not ready to show its settings.',
                onTap: () => ref.read(settingsProvider.notifier).reload(),
              ),
            ],
          ),
        ],
      );
    }

    return SettingsScreen(
      title: 'Settings',
      children: [
        SettingsGroup(
          title: 'Basics',
          children: [
            SettingsRow(
              icon: Icons.search,
              title: 'Search engine',
              subtitle:
                  settings.searchEngineName ??
                  LadybirdController.fallbackSearchEngine.name,
              onTap: () => _open(const SearchSettingsPage()),
            ),
            SettingsRow(
              icon: Icons.security_outlined,
              title: 'Privacy and security',
              subtitle: 'History, tracking and content blocking',
              onTap: () => _open(const PrivacySettingsPage()),
            ),
            SettingsRow(
              icon: Icons.call_to_action_outlined,
              title: 'Address bar',
              subtitle: addressBar == AddressBarPosition.top ? 'Top' : 'Bottom',
              onTap: () => _open(const AddressBarSettingsPage()),
            ),
            SettingsRow(
              icon: Icons.grid_view_rounded,
              title: 'New tab page',
              onTap: () => _open(const NewTabSettingsPage()),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Advanced',
          children: [
            SettingsRow(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              subtitle: switch (settings.interfaceTheme) {
                'light' => 'Light',
                'dark' => 'Dark',
                _ => 'System default',
              },
              onTap: () => _open(const AppearanceSettingsPage()),
            ),
            SettingsRow(
              icon: Icons.accessibility_new_rounded,
              title: 'Accessibility',
              subtitle: 'Page zoom',
              onTap: () => _open(const AccessibilitySettingsPage()),
            ),
            SettingsRow(
              icon: Icons.tune_rounded,
              title: 'Site settings',
              subtitle: 'What pages may do on their own',
              onTap: () => _open(const SiteSettingsPage()),
            ),
            SettingsRow(
              icon: Icons.download_done_rounded,
              title: 'Downloads',
              onTap: () => _open(const DownloadsPage()),
            ),
            SettingsRow(
              icon: Icons.science_outlined,
              title: 'Engine options',
              subtitle: 'Options that rarely need changing',
              onTap: () => _open(const EngineSettingsPage()),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.info_outline,
              title: 'About Rubisco',
              onTap: () => _open(const AboutSettingsPage()),
            ),
          ],
        ),
      ],
    );
  }
}

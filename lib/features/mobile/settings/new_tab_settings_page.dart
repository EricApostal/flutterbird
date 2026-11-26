import 'package:bird_core/bird_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/settings/settings_widgets.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/new_tab/new_tab_settings.dart';

/// The switches for what the new tab page has on it.
class _NewTabChoices extends ConsumerWidget {
  const _NewTabChoices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(newTabSettingsProvider);
    final notifier = ref.read(newTabSettingsProvider.notifier);

    Widget row(
      IconData icon,
      String title,
      bool value,
      NewTabSettings Function(bool value) changed,
    ) => SettingsSwitchRow(
      icon: icon,
      title: title,
      value: value,
      onChanged: (next) => notifier.change(changed(next)),
    );

    final hidden = settings.hiddenSites.length;
    return SettingsGroup(
      children: [
        row(
          Icons.grid_view_rounded,
          'Most visited sites',
          settings.showFrequentSites,
          (on) => settings.copyWith(showFrequentSites: on),
        ),
        row(
          Icons.star_outline_rounded,
          'Bookmarks',
          settings.showBookmarks,
          (on) => settings.copyWith(showBookmarks: on),
        ),
        row(
          Icons.history,
          'Continue browsing',
          settings.showRecent,
          (on) => settings.copyWith(showRecent: on),
        ),
        row(
          Icons.tab_rounded,
          'Recently closed',
          settings.showRecentlyClosed,
          (on) => settings.copyWith(showRecentlyClosed: on),
        ),
        if (hidden > 0)
          SettingsRow(
            icon: Icons.restore_rounded,
            title: hidden == 1
                ? 'Restore 1 removed site'
                : 'Restore $hidden removed sites',
            onTap: () =>
                notifier.change(settings.copyWith(hiddenSites: const {})),
          ),
      ],
    );
  }
}

/// The same switches, on a sheet over the new tab page itself.
Future<void> showNewTabCustomizeSheet(BuildContext context) =>
    showMobileSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Text(
                'Customize new tab page',
                style: TextStyle(fontSize: 20, color: context.mobile.text),
              ),
            ),
            const _NewTabChoices(),
          ],
        ),
      ),
    );

class NewTabSettingsPage extends ConsumerStatefulWidget {
  const NewTabSettingsPage({super.key});

  @override
  ConsumerState<NewTabSettingsPage> createState() => _NewTabSettingsPageState();
}

class _NewTabSettingsPageState extends ConsumerState<NewTabSettingsPage> {
  @override
  void initState() {
    super.initState();
    // Settings can be opened before any new tab page has read what was kept.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabs = ref.read(browserTabControllerProvider);
      if (tabs.isEmpty) return;
      ref
          .read(newTabSettingsProvider.notifier)
          .load(tabs.first.getProfileConfigDirectory());
    });
  }

  @override
  Widget build(BuildContext context) =>
      const SettingsScreen(title: 'New tab page', children: [_NewTabChoices()]);
}

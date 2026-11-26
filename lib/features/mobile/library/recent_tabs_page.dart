import 'package:bird_session/bird_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/library/library_widgets.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';

/// The tabs closed since the browser started, the last first.
class RecentTabsPage extends ConsumerWidget {
  const RecentTabsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.mobile;
    final shell = ref.read(browserShellProvider);
    final closed = shell.recentlyClosed;

    return LibraryScreen(
      title: 'Recent tabs',
      child: closed.isEmpty
          ? const LibraryEmpty(
              icon: Icons.tab_rounded,
              message: 'Tabs you close appear here',
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text(
                    'Recently closed',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                for (final record in closed)
                  LibraryRow(
                    leading: SiteIcon(url: record.url, size: 20),
                    title: pageTitle(record.title, record.url),
                    subtitle: displayAddress(record.url),
                    onTap: () {
                      shell.forgetClosedTab(record);
                      openInNewTab(context, record.url);
                    },
                  ),
              ],
            ),
    );
  }
}

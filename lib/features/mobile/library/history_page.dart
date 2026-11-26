import 'package:bird_session/bird_session.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/library/library_widgets.dart';
import 'package:rubisco_browser/features/mobile/library/link_menu.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';

const int _mostShown = 1000;

/// Removes every page from the history. Returns whether it is empty after.
///
/// The engine removes one address at a time, so this goes through what it
/// lists until it lists nothing.
bool _clearHistory() {
  String? first;
  while (true) {
    final pages = parseVisitedPages(historyEntriesJson(limit: 500));
    if (pages.isEmpty) return true;
    // An address that will not go would otherwise keep this going for ever.
    if (pages.first.url == first) return false;
    first = pages.first.url;
    for (final page in pages) {
      if (!removeHistoryEntry(page.url)) return false;
    }
  }
}

/// Deletes the browsing history, if the user says so. Returns whether it did.
Future<bool> confirmAndClearHistory(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final agreed = await confirmMobileAction(
    context: context,
    title: 'Delete browsing history?',
    message:
        'The list of pages you have visited is removed, along with the '
        'suggestions made from it. This cannot be undone.',
    confirm: 'Delete',
  );
  if (!agreed) return false;
  final cleared = _clearHistory();
  showMobileSnack(
    messenger,
    cleared ? 'Browsing history deleted' : 'Some history could not be deleted',
    bottomGap: 12,
  );
  return true;
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<VisitedPage> _pages = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _pages = _read();
  }

  List<VisitedPage> _read() =>
      parseVisitedPages(historyEntriesJson(limit: _mostShown));

  void _reload() {
    if (mounted) setState(() => _pages = _read());
  }

  void _remove(String url) {
    if (removeHistoryEntry(url)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final days = historyByDay(_pages, now: DateTime.now(), query: _query);
    // One list of headings and pages, so that only what is seen is built.
    final items = <Object>[
      for (final day in days) ...[day.label, ...day.pages],
    ];

    return LibraryScreen(
      title: 'History',
      onSearch: (query) => setState(() => _query = query),
      actions: [
        if (_pages.isNotEmpty)
          IconButton(
            tooltip: 'Delete browsing history',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              if (await confirmAndClearHistory(context)) _reload();
            },
          ),
      ],
      child: items.isEmpty
          ? LibraryEmpty(
              icon: Icons.history,
              message: _query.isEmpty
                  ? 'Pages you visit appear here'
                  : 'No pages match your search',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is! VisitedPage) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                    child: Text(
                      '$item',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  );
                }
                return Builder(
                  key: ValueKey(item.url),
                  builder: (anchor) => LibraryRow(
                    leading: SiteIcon(
                      url: item.url,
                      favicon: item.favicon,
                      size: 20,
                    ),
                    title: pageTitle(item.title, item.url),
                    subtitle: displayAddress(item.url),
                    onTap: () => openInCurrentTab(context, item.url),
                    onLongPress: () => showLinkMenu(
                      context,
                      item.url,
                      anchor: anchor,
                      removeLabel: 'Remove from history',
                      onRemove: () => _remove(item.url),
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove from history',
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: colors.textSecondary,
                      ),
                      onPressed: () => _remove(item.url),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

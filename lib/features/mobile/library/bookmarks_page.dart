import 'package:bird_core/bird_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';
import 'package:rubisco_browser/features/mobile/library/library_widgets.dart';
import 'package:rubisco_browser/features/mobile/library/link_menu.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';

class BookmarksPage extends ConsumerStatefulWidget {
  const BookmarksPage({super.key});

  @override
  ConsumerState<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends ConsumerState<BookmarksPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Not while widgets are being built, when providers cannot change.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    final tabs = ref.read(browserTabControllerProvider);
    if (tabs.isEmpty) return;
    ref.read(browserOmniboxProvider.notifier).refreshBookmarks(tabs.first);
  }

  void _remove(BirdBookmark bookmark) {
    final tabs = ref.read(browserTabControllerProvider);
    if (tabs.isEmpty) return;
    ref
        .read(bookmarkStoreProvider)
        .toggle(
          directory: tabs.first.getProfileConfigDirectory(),
          url: bookmark.url,
          title: bookmark.title,
        );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final all = ref.watch(
      browserOmniboxProvider.select((state) => state.bookmarks),
    );
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final bookmark in all)
        if (query.isEmpty ||
            bookmark.title.toLowerCase().contains(query) ||
            bookmark.url.toLowerCase().contains(query))
          bookmark,
    ];

    return LibraryScreen(
      title: 'Bookmarks',
      onSearch: (value) => setState(() => _query = value),
      child: shown.isEmpty
          ? LibraryEmpty(
              icon: Icons.star_outline_rounded,
              message: query.isEmpty
                  ? 'Pages you bookmark appear here'
                  : 'No bookmarks match your search',
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final bookmark = shown[index];
                void menu(BuildContext anchor) => showLinkMenu(
                  context,
                  bookmark.url,
                  anchor: anchor,
                  removeLabel: 'Delete bookmark',
                  onRemove: () => _remove(bookmark),
                );
                return Builder(
                  key: ValueKey(bookmark.url),
                  builder: (anchor) => LibraryRow(
                    leading: SiteIcon(
                      url: bookmark.url,
                      favicon: bookmark.favicon,
                      size: 20,
                    ),
                    title: pageTitle(bookmark.title, bookmark.url),
                    subtitle: displayAddress(bookmark.url),
                    onTap: () => openInCurrentTab(context, bookmark.url),
                    onLongPress: () => menu(anchor),
                    trailing: Builder(
                      builder: (button) => IconButton(
                        tooltip: 'More',
                        icon: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: colors.textSecondary,
                        ),
                        onPressed: () => menu(button),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

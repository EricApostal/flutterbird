import 'dart:math' as math;

import 'package:bird_core/bird_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';
import 'package:rubisco_browser/features/mobile/browser/mobile_browser_scope.dart';
import 'package:rubisco_browser/features/mobile/library/bookmarks_page.dart';
import 'package:rubisco_browser/features/mobile/library/history_page.dart';
import 'package:rubisco_browser/features/mobile/library/recent_tabs_page.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/settings/new_tab_settings_page.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';
import 'package:rubisco_browser/features/mobile/widgets/site_icon.dart';
import 'package:rubisco_browser/features/new_tab/new_tab_settings.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';

const double _contentWidth = 560;
const int _columns = 4;
const int _mostTiles = 8;
const int _mostListed = 4;

/// What a new tab shows on a phone, as Chrome's does: a search box under the
/// browser's name, the sites gone to most, and ways back to where one has been.
///
/// It is drawn over the tab's page, which is blank until it goes somewhere.
class MobileNewTabPage extends ConsumerStatefulWidget {
  const MobileNewTabPage({required this.tab, super.key});

  final LadybirdController tab;

  @override
  ConsumerState<MobileNewTabPage> createState() => _MobileNewTabPageState();
}

class _MobileNewTabPageState extends ConsumerState<MobileNewTabPage> {
  List<VisitedPage> _history = const [];

  @override
  void initState() {
    super.initState();
    // Not while widgets are being built, when providers cannot change.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(newTabSettingsProvider.notifier)
          .load(widget.tab.getProfileConfigDirectory());
      ref.read(browserOmniboxProvider.notifier).refreshBookmarks(widget.tab);
      _loadHistory();
    });
  }

  void _loadHistory() {
    setState(() => _history = parseVisitedPages(historyEntriesJson()));
  }

  void _open(String url) => widget.tab.navigate(url);

  Future<void> _linkMenu(
    BuildContext anchor,
    String url, {
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
    if (!mounted) return;
    switch (choice) {
      case 'tab':
        openInBackgroundTab(context, url);
      case 'copy':
        await copyText(context, url);
      case 'share':
        await shareText(context, url);
      case 'remove':
        onRemove();
    }
  }

  void _removeBookmark(BirdBookmark bookmark) {
    ref
        .read(bookmarkStoreProvider)
        .toggle(
          directory: widget.tab.getProfileConfigDirectory(),
          url: bookmark.url,
          title: bookmark.title,
        );
    ref.read(browserOmniboxProvider.notifier).refreshBookmarks(widget.tab);
  }

  void _hideSite(String host) {
    final settings = ref.read(newTabSettingsProvider);
    ref
        .read(newTabSettingsProvider.notifier)
        .change(
          settings.copyWith(hiddenSites: {...settings.hiddenSites, host}),
        );
  }

  void _removeFromHistory(String url) {
    if (removeHistoryEntry(url)) _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    final settings = ref.watch(newTabSettingsProvider);
    final bookmarks = ref.watch(
      browserOmniboxProvider.select((state) => state.bookmarks),
    );
    // Closing a tab changes the session, and adds to what can be reopened.
    ref.watch(browserSessionProvider);
    final shell = ref.read(browserShellProvider);
    final now = DateTime.now();

    final icons = <String, String>{};
    for (final page in _history) {
      final favicon = page.favicon;
      if (favicon == null || favicon.isEmpty) continue;
      final host = siteHost(page.url);
      if (host.isNotEmpty) icons.putIfAbsent(host, () => favicon);
    }

    final sites = settings.showFrequentSites
        ? frequentSites(
            _history,
            now: now,
            hidden: settings.hiddenSites,
            limit: _mostTiles,
          )
        : const <FrequentSite>[];
    final recent = settings.showRecent
        ? recentPages(_history, limit: _mostListed)
        : const <VisitedPage>[];
    final closed = settings.showRecentlyClosed
        ? shell.recentlyClosed.take(_mostListed).toList()
        : const <ClosedTabRecord>[];

    final siteTiles = [
      for (final site in sites)
        _SiteTile(
          label: site.host,
          url: site.url,
          favicon: site.favicon,
          onTap: () => _open(site.url),
          onLongPress: (anchor) => _linkMenu(
            anchor,
            site.url,
            removeLabel: 'Remove',
            onRemove: () => _hideSite(site.host),
          ),
        ),
    ];

    final bookmarkTiles = [
      if (settings.showBookmarks)
        for (final bookmark in bookmarks.take(_mostTiles))
          _SiteTile(
            label: pageTitle(bookmark.title, bookmark.url),
            url: bookmark.url,
            favicon: bookmark.favicon ?? icons[siteHost(bookmark.url)],
            onTap: () => _open(bookmark.url),
            onLongPress: (anchor) => _linkMenu(
              anchor,
              bookmark.url,
              removeLabel: 'Remove bookmark',
              onRemove: () => _removeBookmark(bookmark),
            ),
          ),
    ];

    // A Material, so that what is pressed on the page shows it.
    return Material(
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The name sits lower on a tall screen, as Chrome's logo does.
          final above = math.max(0.0, constraints.maxHeight * 0.07 - 12);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _contentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Customize new tab page',
                        iconSize: 21,
                        icon: Icon(
                          Icons.edit_outlined,
                          color: colors.textSecondary,
                        ),
                        onPressed: () => showNewTabCustomizeSheet(context),
                      ),
                    ),
                    SizedBox(height: above),
                    const _Brand(),
                    const SizedBox(height: 28),
                    _SearchBox(
                      engine: widget.tab.activeSearchEngine.name,
                      onTap: () =>
                          MobileBrowserScope.maybeOf(context)?.editAddress(),
                    ),
                    if (siteTiles.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _Tiles(tiles: siteTiles),
                    ],
                    if (bookmarkTiles.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Card(
                        title: 'Bookmarks',
                        onShowAll: () => pushMobilePage<void>(
                          context,
                          const BookmarksPage(),
                        ),
                        child: _Tiles(tiles: bookmarkTiles),
                      ),
                    ],
                    if (recent.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Card(
                        title: 'Continue browsing',
                        onShowAll: () =>
                            pushMobilePage<void>(context, const HistoryPage()),
                        child: Column(
                          children: [
                            for (final page in recent)
                              _LinkRow(
                                title: pageTitle(page.title, page.url),
                                detail:
                                    '${siteHost(page.url)} · '
                                    '${timeAgo(page.lastVisited, now)}',
                                url: page.url,
                                favicon:
                                    page.favicon ?? icons[siteHost(page.url)],
                                onTap: () => _open(page.url),
                                onLongPress: (anchor) => _linkMenu(
                                  anchor,
                                  page.url,
                                  removeLabel: 'Remove from history',
                                  onRemove: () => _removeFromHistory(page.url),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (closed.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _Card(
                        title: 'Recently closed',
                        onShowAll: () => pushMobilePage<void>(
                          context,
                          const RecentTabsPage(),
                        ),
                        child: Column(
                          children: [
                            for (final record in closed)
                              _LinkRow(
                                title: pageTitle(record.title, record.url),
                                detail: displayAddress(record.url),
                                url: record.url,
                                favicon: icons[siteHost(record.url)],
                                onTap: () {
                                  shell.forgetClosedTab(record);
                                  _open(record.url);
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'browser-logo.png',
          width: 88,
          height: 88,
          cacheWidth: 264,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(height: 8),
        Text(
          'Rubisco',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
            color: context.mobile.text,
          ),
        ),
      ],
    );
  }
}

/// What looks like a search field and opens the address bar, which is the one
/// place text is typed.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.engine, required this.onTap});

  final String engine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Material(
      color: colors.field,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 20),
              Icon(Icons.search, color: colors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Search $engine or type URL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiles, four to a row.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var start = 0; start < tiles.length; start += _columns)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = start; i < start + _columns; i++)
                Expanded(
                  child: i < tiles.length ? tiles[i] : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.label,
    required this.url,
    required this.favicon,
    required this.onTap,
    required this.onLongPress,
  });

  final String label;
  final String url;
  final String? favicon;
  final VoidCallback onTap;
  final ValueChanged<BuildContext> onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Builder(
      builder: (context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: () => onLongPress(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.field,
                  shape: BoxShape.circle,
                ),
                child: SiteIcon(url: url, favicon: favicon, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.onShowAll,
    required this.child,
  });

  final String title;
  final VoidCallback onShowAll;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Material(
      color: colors.container,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colors.text,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onShowAll,
                    child: const Text('Show all'),
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.title,
    required this.detail,
    required this.url,
    required this.favicon,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String detail;
  final String url;
  final String? favicon;
  final VoidCallback onTap;
  final ValueChanged<BuildContext>? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return Builder(
      builder: (context) => InkWell(
        onTap: onTap,
        onLongPress: onLongPress == null ? null : () => onLongPress!(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SiteIcon(url: url, favicon: favicon, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: colors.text),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

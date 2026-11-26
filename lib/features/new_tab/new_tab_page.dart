import 'dart:async';

import 'package:bird_core/bird_core.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ladybird/ladybird.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_search_field.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';
import 'package:rubisco_browser/features/new_tab/new_tab_settings.dart';
import 'package:rubisco_browser/features/new_tab/new_tab_tiles.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';

const double _contentWidth = 720;
const double _searchWidth = 600;
const double _sideBySideWidth = 560;
const int _mostBookmarks = 16;
const int _mostListed = 6;

/// What a new tab shows: a search field, and ways back to where one has been.
/// It is drawn over the tab's page, which is blank until it goes somewhere.
class NewTabPage extends ConsumerStatefulWidget {
  const NewTabPage({required this.tab, super.key});

  final LadybirdController tab;

  @override
  ConsumerState<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends ConsumerState<NewTabPage> {
  final TextEditingController _searchText = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final OverlayPortalController _customize = OverlayPortalController();

  List<VisitedPage> _history = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(newTabSettingsProvider.notifier)
          .load(widget.tab.getProfileConfigDirectory());
      ref.read(browserOmniboxProvider.notifier).refreshBookmarks(widget.tab);
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _loadHistory() {
    setState(() => _history = parseVisitedPages(historyEntriesJson()));
  }

  void _open(String url, {bool ownTab = false}) {
    if (url.isEmpty) return;
    if (ownTab) {
      ref
          .read(browserShellProvider)
          .openTab(
            windowId: BrowserWindowScope.of(context),
            url: url,
            activate: false,
          );
      return;
    }
    _searchFocus.unfocus();
    _searchText.clear();
    widget.tab.navigate(url);
  }

  NewTabLink _link({
    required String url,
    required String label,
    String? favicon,
    String detail = '',
    List<BirdMenuEntry> menu = const [],
    VoidCallback? onOpened,
  }) => NewTabLink(
    url: url,
    label: label,
    favicon: favicon,
    detail: detail,
    menu: menu,
    onOpen: ({required ownTab}) {
      onOpened?.call();
      _open(url, ownTab: ownTab);
    },
  );

  // The icon the history has for each site, for what has none of its own.
  Map<String, String> _siteIcons() {
    final icons = <String, String>{};
    for (final page in _history) {
      final favicon = page.favicon;
      if (favicon == null || favicon.isEmpty) continue;
      final host = siteHost(page.url);
      if (host.isNotEmpty) icons.putIfAbsent(host, () => favicon);
    }
    return icons;
  }

  String _titleOr(String title, String url) {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final host = siteHost(url);
    return host.isNotEmpty ? host : url;
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

  void _removeFromHistory(String url) {
    if (removeHistoryEntry(url)) _loadHistory();
  }

  void _hideSite(String host) {
    final settings = ref.read(newTabSettingsProvider);
    ref
        .read(newTabSettingsProvider.notifier)
        .change(
          settings.copyWith(hiddenSites: {...settings.hiddenSites, host}),
        );
  }

  Widget _searchField() {
    final omnibox = ref.read(browserOmniboxProvider.notifier);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _searchWidth),
      child: OmniboxSearchField(
        prominent: true,
        currentTabController: widget.tab,
        omniBoxTextController: _searchText,
        omniboxFocusNode: _searchFocus,
        omniboxController: omnibox,
        onSubmitted: (value) =>
            _open(omnibox.buildNavigationTarget(widget.tab, value.trim())),
        onSuggestionSelected: (suggestion) => _open(
          suggestion.isSearch
              ? omnibox.buildNavigationTarget(widget.tab, suggestion.value)
              : suggestion.value,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    final settings = ref.watch(newTabSettingsProvider);
    final bookmarks = ref.watch(
      browserOmniboxProvider.select((state) => state.bookmarks),
    );
    // Closing a tab changes the session, and adds to what can be reopened.
    ref.watch(browserSessionProvider);
    final shell = ref.read(browserShellProvider);

    final now = DateTime.now();
    final icons = _siteIcons();

    final bookmarkLinks = !settings.showBookmarks
        ? const <NewTabLink>[]
        : [
            for (final bookmark in bookmarks.take(_mostBookmarks))
              _link(
                url: bookmark.url,
                label: _titleOr(bookmark.title, bookmark.url),
                favicon: bookmark.favicon ?? icons[siteHost(bookmark.url)],
                menu: [
                  BirdMenuItem(
                    'Remove Bookmark',
                    onSelected: () => _removeBookmark(bookmark),
                  ),
                ],
              ),
          ];

    final frequentLinks = !settings.showFrequentSites
        ? const <NewTabLink>[]
        : [
            for (final site in frequentSites(
              _history,
              now: now,
              hidden: settings.hiddenSites,
            ))
              _link(
                url: site.url,
                label: site.host,
                favicon: site.favicon,
                menu: [
                  BirdMenuItem(
                    'Hide Site',
                    onSelected: () => _hideSite(site.host),
                  ),
                ],
              ),
          ];

    final recentLinks = !settings.showRecent
        ? const <NewTabLink>[]
        : [
            for (final page in recentPages(_history, limit: _mostListed))
              _link(
                url: page.url,
                label: _titleOr(page.title, page.url),
                favicon: page.favicon ?? icons[siteHost(page.url)],
                detail: timeAgo(page.lastVisited, now),
                menu: [
                  BirdMenuItem(
                    'Remove from History',
                    onSelected: () => _removeFromHistory(page.url),
                  ),
                ],
              ),
          ];

    final closedLinks = !settings.showRecentlyClosed
        ? const <NewTabLink>[]
        : [
            for (final record in shell.recentlyClosed.take(_mostListed))
              _link(
                url: record.url,
                label: _titleOr(record.title, record.url),
                favicon: icons[siteHost(record.url)],
                onOpened: () => shell.forgetClosedTab(record),
              ),
          ];

    final cards = [
      if (recentLinks.isNotEmpty)
        LinkListCard(title: 'Recently visited', links: recentLinks),
      if (closedLinks.isNotEmpty)
        LinkListCard(title: 'Recently closed', links: closedLinks),
    ];

    // Opaque, so that nothing reaches the page underneath.
    return ColoredBox(
      color: colors.toolbar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.1),
            radius: 1.1,
            colors: [
              BirdBrand.blue.withValues(alpha: colors.isDark ? 0.16 : 0.10),
              BirdBrand.blue.withValues(alpha: 0),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _searchFocus.unfocus,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final height = constraints.maxHeight;
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        (height * 0.11).clamp(24.0, 110.0),
                        24,
                        56,
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _contentWidth,
                          ),
                          child: Column(
                            children: [
                              _Heading(showClock: settings.showClock),
                              const SizedBox(height: 28),
                              _searchField(),
                              if (bookmarkLinks.isNotEmpty)
                                _TileSection(
                                  title: 'Bookmarks',
                                  links: bookmarkLinks,
                                ),
                              if (frequentLinks.isNotEmpty)
                                _TileSection(
                                  title: 'Frequently visited',
                                  links: frequentLinks,
                                ),
                              if (cards.isNotEmpty) ...[
                                const SizedBox(height: 28),
                                _Cards(cards: cards),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _CustomizeButton(controller: _customize),
            ),
          ],
        ),
      ),
    );
  }
}

/// The time, if wanted, over a greeting and the date. It keeps itself current.
class _Heading extends StatefulWidget {
  const _Heading({required this.showClock});

  final bool showClock;

  @override
  State<_Heading> createState() => _HeadingState();
}

class _HeadingState extends State<_Heading> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _waitForNextMinute();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _waitForNextMinute() {
    final now = DateTime.now();
    _timer = Timer(
      Duration(seconds: 60 - now.second, milliseconds: -now.millisecond),
      () {
        if (!mounted) return;
        setState(() {});
        _waitForNextMinute();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    final now = DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showClock) ...[
          Text(
            clockText(now, use24Hour: use24Hour),
            style: context.birdText(
              size: 60,
              weight: FontWeight.w200,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          '${greetingFor(now)} · ${longDateText(now)}',
          textAlign: TextAlign.center,
          style: context.birdText(
            color: colors.textSecondary,
            size: BirdTextSize.headline,
          ),
        ),
      ],
    );
  }
}

class _TileSection extends StatelessWidget {
  const _TileSection({required this.title, required this.links});

  final String title;
  final List<NewTabLink> links;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionTitle(title),
          const SizedBox(height: 8),
          ConstrainedBox(
            // Never more than seven across, so that rows stay easy to scan.
            constraints: const BoxConstraints(
              maxWidth: kSiteTileWidth * 7 + 4 * 6,
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [for (final link in links) SiteTile(link: link)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Side by side where there is room, and one under the other where not.
class _Cards extends StatelessWidget {
  const _Cards({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            cards.length > 1 && constraints.maxWidth >= _sideBySideWidth;
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, card) in cards.indexed) ...[
                if (index > 0) const SizedBox(width: 12),
                Expanded(child: card),
              ],
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, card) in cards.indexed) ...[
              if (index > 0) const SizedBox(height: 12),
              card,
            ],
          ],
        );
      },
    );
  }
}

/// The button that opens the choice of what the page has on it.
class _CustomizeButton extends StatelessWidget {
  const _CustomizeButton({required this.controller});

  final OverlayPortalController controller;

  @override
  Widget build(BuildContext context) {
    return BirdPopover(
      controller: controller,
      align: BirdPopoverAlign.end,
      popoverBuilder: (context) => const _CustomizePanel(),
      child: BirdToolbarButton(
        glyph: BirdGlyph.gear,
        tooltip: 'Customize this page',
        onPressed: controller.toggle,
      ),
    );
  }
}

class _CustomizePanel extends ConsumerWidget {
  const _CustomizePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(newTabSettingsProvider);
    final notifier = ref.read(newTabSettingsProvider.notifier);

    Widget row(
      String label,
      bool value,
      NewTabSettings Function(bool value) changed,
    ) => SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.birdText())),
          BirdSwitch(
            value: value,
            onChanged: (next) => notifier.change(changed(next)),
            semanticLabel: label,
          ),
        ],
      ),
    );

    final hidden = settings.hiddenSites.length;
    return BirdPanel(
      width: 240,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Show on new tabs'),
          const SizedBox(height: 4),
          row(
            'Clock',
            settings.showClock,
            (on) => settings.copyWith(showClock: on),
          ),
          row(
            'Bookmarks',
            settings.showBookmarks,
            (on) => settings.copyWith(showBookmarks: on),
          ),
          row(
            'Frequently visited',
            settings.showFrequentSites,
            (on) => settings.copyWith(showFrequentSites: on),
          ),
          row(
            'Recently visited',
            settings.showRecent,
            (on) => settings.copyWith(showRecent: on),
          ),
          row(
            'Recently closed',
            settings.showRecentlyClosed,
            (on) => settings.copyWith(showRecentlyClosed: on),
          ),
          if (hidden > 0) ...[
            const SizedBox(height: 8),
            BirdButton(
              hidden == 1
                  ? 'Restore 1 hidden site'
                  : 'Restore $hidden hidden sites',
              small: true,
              expand: true,
              onPressed: () =>
                  notifier.change(settings.copyWith(hiddenSites: const {})),
            ),
          ],
        ],
      ),
    );
  }
}

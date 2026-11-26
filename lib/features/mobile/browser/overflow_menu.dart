import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';
import 'package:rubisco_browser/features/mobile/widgets/mobile_overlays.dart';

enum OverflowAction {
  back,
  forward,
  bookmark,
  pageInfo,
  reload,
  newTab,
  closeTab,
  history,
  downloads,
  bookmarks,
  recentTabs,
  share,
  findInPage,
  copy,
  paste,
  selectAll,
  settings,
}

/// What the menu needs to know about the page it is opened over.
class OverflowMenuPage {
  const OverflowMenuPage({
    required this.canGoBack,
    required this.canGoForward,
    required this.isBookmarked,
    required this.isWebPage,
  });

  final bool canGoBack;
  final bool canGoForward;
  final bool isBookmarked;

  /// Whether there is a page of the web's, which can be shared, bookmarked and
  /// searched, rather than the browser's own.
  final bool isWebPage;
}

/// The toolbar's menu, as Chrome lays it out: a row of buttons about the page,
/// and then the rest of the browser.
Future<OverflowAction?> showOverflowMenu({
  required BuildContext context,
  required Rect anchor,
  required OverflowMenuPage page,
}) {
  return showMobileMenu<OverflowAction>(
    context: context,
    anchor: anchor,
    width: 280,
    builder: (context) {
      void choose(OverflowAction action) => Navigator.of(context).pop(action);

      Widget row(
        IconData icon,
        String label,
        OverflowAction action, {
        bool enabled = true,
      }) => MobileMenuRow(
        icon: icon,
        label: label,
        onTap: enabled ? () => choose(action) : null,
      );

      Widget button(
        IconData icon,
        String label,
        OverflowAction action, {
        bool enabled = true,
        Color? color,
      }) => Expanded(
        child: IconButton(
          tooltip: label,
          color: color ?? context.mobile.text,
          icon: Icon(icon),
          onPressed: enabled ? () => choose(action) : null,
        ),
      );

      const divider = Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(),
      );

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                button(
                  Icons.arrow_back,
                  'Back',
                  OverflowAction.back,
                  enabled: page.canGoBack,
                ),
                button(
                  Icons.arrow_forward,
                  'Forward',
                  OverflowAction.forward,
                  enabled: page.canGoForward,
                ),
                button(
                  page.isBookmarked
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  page.isBookmarked ? 'Remove bookmark' : 'Bookmark',
                  OverflowAction.bookmark,
                  enabled: page.isWebPage,
                  color: page.isBookmarked ? context.mobile.accent : null,
                ),
                button(
                  Icons.info_outline,
                  'Site information',
                  OverflowAction.pageInfo,
                  enabled: page.isWebPage,
                ),
                button(
                  Icons.refresh,
                  'Reload',
                  OverflowAction.reload,
                  enabled: page.isWebPage,
                ),
              ],
            ),
          ),
          divider,
          row(Icons.add_box_outlined, 'New tab', OverflowAction.newTab),
          row(Icons.close, 'Close tab', OverflowAction.closeTab),
          divider,
          row(Icons.history, 'History', OverflowAction.history),
          row(
            Icons.download_done_rounded,
            'Downloads',
            OverflowAction.downloads,
          ),
          row(Icons.star_rounded, 'Bookmarks', OverflowAction.bookmarks),
          row(Icons.tab_rounded, 'Recent tabs', OverflowAction.recentTabs),
          divider,
          row(
            Icons.share_outlined,
            'Share…',
            OverflowAction.share,
            enabled: page.isWebPage,
          ),
          row(
            Icons.find_in_page_outlined,
            'Find in page',
            OverflowAction.findInPage,
            enabled: page.isWebPage,
          ),
          if (page.isWebPage)
            Padding(
              padding: const EdgeInsets.only(left: 18, right: 8),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const Icon(Icons.content_paste_rounded, size: 22),
                    const SizedBox(width: 8),
                    for (final (label, action) in const [
                      ('Copy', OverflowAction.copy),
                      ('Paste', OverflowAction.paste),
                      ('Select all', OverflowAction.selectAll),
                    ])
                      Flexible(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: context.mobile.text,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 40),
                          ),
                          onPressed: () => choose(action),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          divider,
          row(Icons.settings_outlined, 'Settings', OverflowAction.settings),
        ],
      );
    },
  );
}

import 'package:bird_core/bird_core.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/favicon_or_icon.dart';

class OmniboxBookmarksBar extends StatelessWidget {
  final List<BirdBookmark> bookmarks;
  final ValueChanged<String> onBookmarkTap;

  const OmniboxBookmarksBar({
    super.key,
    required this.bookmarks,
    required this.onBookmarkTap,
  });

  @override
  Widget build(BuildContext context) {
    if (bookmarks.isEmpty) {
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final bookmark in bookmarks)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: _BookmarkButton(
                bookmark: bookmark,
                onTap: () => onBookmarkTap(bookmark.url),
              ),
            ),
        ],
      ),
    );
  }
}

class _BookmarkButton extends StatelessWidget {
  final BirdBookmark bookmark;
  final VoidCallback onTap;

  const _BookmarkButton({required this.bookmark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;

    return BirdTooltip(
      message: bookmark.url,
      child: BirdPressable(
        onPressed: onTap,
        builder: (context, state) => BirdFocusRing(
          visible: state.focused,
          child: Container(
            height: 24,
            constraints: const BoxConstraints(maxWidth: 190),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: state.pressed
                  ? colors.pressed
                  : (state.hovered ? colors.hover : null),
              borderRadius: BorderRadius.circular(BirdRadius.control),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaviconOrIcon(
                  favicon: bookmark.favicon,
                  fallback: BirdGlyph.globe,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    bookmark.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.birdText(size: BirdTextSize.small),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

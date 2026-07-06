import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/favicon_or_icon.dart';
import 'package:flutterbird/features/browser/state/omnibox_state.dart';

class OmniboxBookmarksBar extends StatelessWidget {
  final List<BrowserBookmark> bookmarks;
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
              child: _BookmarkChip(
                bookmark: bookmark,
                onTap: () => onBookmarkTap(bookmark.url),
              ),
            ),
        ],
      ),
    );
  }
}

class _BookmarkChip extends StatelessWidget {
  final BrowserBookmark bookmark;
  final VoidCallback onTap;

  const _BookmarkChip({required this.bookmark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: bookmark.url,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          side: BorderSide(width: 0, color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaviconOrIcon(
              favicon: bookmark.favicon,
              fallback: Icons.bookmark,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              bookmark.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/favicon_or_icon.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_url_text.dart';
import 'package:flutterbird/features/browser/state/omnibox_state.dart';

class OmniboxSuggestionRow extends StatelessWidget {
  final OmniboxSuggestion option;
  final VoidCallback onTap;

  const OmniboxSuggestionRow({
    super.key,
    required this.option,
    required this.onTap,
  });

  static bool _isUrlSuggestion(OmniboxSuggestion option) {
    return option.type == OmniboxSuggestionType.bookmark ||
        option.type == OmniboxSuggestionType.history;
  }

  static IconData _iconFor(OmniboxSuggestionType type) {
    switch (type) {
      case OmniboxSuggestionType.bookmark:
        return Icons.bookmark;
      case OmniboxSuggestionType.history:
        return Icons.history;
      case OmniboxSuggestionType.searchQuery:
      case OmniboxSuggestionType.searchAction:
        return Icons.search;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUrlSuggestion = _isUrlSuggestion(option);
    final urlText = option.subtitle?.trim();
    final hasUrlText =
        isUrlSuggestion && urlText != null && urlText.isNotEmpty;
    final title = option.title.trim();
    final showTitle = title.isNotEmpty && (!hasUrlText || title != urlText);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            FaviconOrIcon(
              favicon: option.favicon,
              fallback: _iconFor(option.type),
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasUrlText)
                    Text.rich(
                      styledUrlSpan(theme, urlText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (showTitle)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hasUrlText
                          ? theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : null,
                    ),
                  if (!hasUrlText && option.subtitle != null)
                    Text(
                      option.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

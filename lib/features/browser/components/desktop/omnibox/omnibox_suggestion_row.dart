import 'package:bird_session/bird_session.dart';
import 'package:flutter/material.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/favicon_or_icon.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/site_info_button.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';

const double _rowHeight = 38;
const Radius _pill = Radius.circular(_rowHeight / 2);

/// One suggestion, on one line: what it is, then where it goes, with what the
/// user typed in bold.
class OmniboxSuggestionRow extends StatefulWidget {
  const OmniboxSuggestionRow({
    required this.option,
    required this.query,
    required this.isSelected,
    required this.onTap,
    this.onRemove,
    super.key,
  });

  final OmniboxSuggestion option;

  /// What the user typed.
  final String query;

  /// Whether Enter would take this one.
  final bool isSelected;
  final VoidCallback onTap;

  /// Forgets the suggestion, for one that can be forgotten.
  final VoidCallback? onRemove;

  @override
  State<OmniboxSuggestionRow> createState() => _OmniboxSuggestionRowState();
}

class _OmniboxSuggestionRowState extends State<OmniboxSuggestionRow> {
  bool _hovered = false;

  static IconData _iconFor(OmniboxSuggestionType type) => switch (type) {
    OmniboxSuggestionType.bookmark => Icons.star_border,
    OmniboxSuggestionType.history ||
    OmniboxSuggestionType.address => Icons.public,
    OmniboxSuggestionType.searchQuery ||
    OmniboxSuggestionType.searchAction => Icons.search,
  };

  /// [text] in [style], bold where it is what was asked for.
  List<TextSpan> _marked(String text, TextStyle style) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final range in matchRanges(text, widget.query)) {
      if (range.start > at) {
        spans.add(
          TextSpan(text: text.substring(at, range.start), style: style),
        );
      }
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: style.copyWith(fontWeight: FontWeight.w700),
        ),
      );
      at = range.end;
    }
    if (at < text.length) {
      spans.add(TextSpan(text: text.substring(at), style: style));
    }
    return spans;
  }

  TextSpan _line(ThemeData theme) {
    final option = widget.option;
    final plain = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 13,
      color: theme.colorScheme.onSurface,
    );
    final quiet = plain.copyWith(
      color: theme.colorScheme.onSurface.withAlpha(150),
    );
    final link = plain.copyWith(color: theme.colorScheme.primary);

    switch (option.type) {
      case OmniboxSuggestionType.searchAction:
      case OmniboxSuggestionType.searchQuery:
        return TextSpan(
          children: [
            TextSpan(text: option.value, style: plain),
            if (option.subtitle case final engine?)
              TextSpan(text: '  -  $engine', style: quiet),
          ],
        );
      case OmniboxSuggestionType.history:
      case OmniboxSuggestionType.bookmark:
      case OmniboxSuggestionType.address:
        final address = displayAddress(option.value);
        final title = option.title.trim();
        // A page with no title of its own is only its address.
        final titled =
            title.isNotEmpty && title != option.value && title != address;
        return TextSpan(
          children: [
            if (titled) ...[
              ..._marked(title, plain),
              TextSpan(text: '  -  ', style: quiet),
            ],
            ..._marked(address, link),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.isSelected || _hovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: _rowHeight,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.onSurface.withAlpha(
                    widget.isSelected ? 30 : 18,
                  )
                : null,
            borderRadius: const BorderRadius.horizontal(right: _pill),
          ),
          child: Row(
            children: [
              // The mark of the one Enter would take, at the panel's edge.
              Container(
                width: 3,
                color: widget.isSelected ? theme.colorScheme.primary : null,
              ),
              // Its icon sits under the one at the start of the field.
              SizedBox(
                width: kSiteInfoButtonWidth - 3,
                child: Center(
                  child: FaviconOrIcon(
                    favicon: widget.option.favicon,
                    fallback: _iconFor(widget.option.type),
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text.rich(
                  _line(theme),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onRemove != null && active)
                IconButton(
                  tooltip: 'Remove from history',
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: widget.onRemove,
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

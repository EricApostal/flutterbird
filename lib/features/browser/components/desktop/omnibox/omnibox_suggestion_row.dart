import 'package:bird_session/bird_session.dart';
import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/favicon_or_icon.dart';
import 'package:rubisco_browser/features/browser/components/desktop/site_info/site_info_button.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';

const double _rowHeight = 32;

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

  static BirdGlyph _iconFor(OmniboxSuggestionType type) => switch (type) {
    OmniboxSuggestionType.bookmark => BirdGlyph.star,
    OmniboxSuggestionType.history ||
    OmniboxSuggestionType.address => BirdGlyph.globe,
    OmniboxSuggestionType.searchQuery ||
    OmniboxSuggestionType.searchAction => BirdGlyph.search,
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

  /// The row's words, [highlighted] when it is the one Enter would take.
  TextSpan _line(BuildContext context, {required bool highlighted}) {
    final colors = context.bird;
    final option = widget.option;
    final plain = context.birdText(
      color: highlighted ? colors.onSelection : colors.text,
    );
    final quiet = plain.copyWith(
      color: highlighted ? colors.onSelection : colors.textSecondary,
    );
    final link = plain.copyWith(
      color: highlighted ? colors.onSelection : colors.accent,
    );

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
    final colors = context.bird;
    final highlighted = widget.isSelected;
    final active = highlighted || _hovered;
    final foreground = highlighted ? colors.onSelection : colors.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: _rowHeight,
          decoration: BoxDecoration(
            color: highlighted
                ? colors.selection
                : (_hovered ? colors.hover : null),
            borderRadius: BorderRadius.circular(BirdRadius.control),
          ),
          child: Row(
            children: [
              // Its icon sits under the one at the start of the field, which
              // is this much further out than the row.
              SizedBox(
                width: kSiteInfoButtonWidth - 6,
                child: Center(
                  child: FaviconOrIcon(
                    favicon: widget.option.favicon,
                    fallback: _iconFor(widget.option.type),
                    size: 15,
                    color: foreground,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  _line(context, highlighted: highlighted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onRemove != null && active)
                BirdToolbarButton(
                  glyph: BirdGlyph.close,
                  tooltip: 'Remove from history',
                  size: 24,
                  iconSize: 10,
                  color: foreground,
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

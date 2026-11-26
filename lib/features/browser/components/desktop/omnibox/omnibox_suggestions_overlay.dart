import 'package:flutter/material.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:rubisco_browser/features/browser/components/desktop/omnibox/omnibox_suggestion_row.dart';
import 'package:rubisco_browser/features/browser/state/omnibox_state.dart';

/// The suggestions, as the lower part of the address field: the same colour,
/// the same width, and nothing between the two.
class OmniboxSuggestionsOverlay extends StatelessWidget {
  const OmniboxSuggestionsOverlay({
    required this.options,
    required this.query,
    required this.selected,
    required this.onSelected,
    required this.onRemove,
    super.key,
  });

  final List<OmniboxSuggestion> options;
  final String query;

  /// The index of the one Enter would take.
  final int selected;
  final ValueChanged<OmniboxSuggestion> onSelected;

  /// Forgets a history suggestion. Null where history cannot be changed.
  final ValueChanged<OmniboxSuggestion>? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRect(
      // A shadow around the sides and below, but none up over the field, which
      // would draw a line where the two meet.
      clipper: const _NothingAbove(),
      child: Material(
        elevation: 10,
        color: omniboxSurfaceColor(theme),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(kOmniboxPanelRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, option) in options.indexed)
                OmniboxSuggestionRow(
                  key: ValueKey('${option.type}:${option.value}'),
                  option: option,
                  query: query,
                  isSelected: index == selected,
                  onTap: () => onSelected(option),
                  onRemove:
                      onRemove != null &&
                          option.type == OmniboxSuggestionType.history
                      ? () => onRemove!(option)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NothingAbove extends CustomClipper<Rect> {
  const _NothingAbove();

  static const double _shadow = 40;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-_shadow, 0, size.width + _shadow, size.height + _shadow);

  @override
  bool shouldReclip(_NothingAbove oldClipper) => false;
}

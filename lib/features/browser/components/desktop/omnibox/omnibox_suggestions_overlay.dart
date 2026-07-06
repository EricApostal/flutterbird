import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_suggestion_row.dart';
import 'package:flutterbird/features/browser/state/omnibox_state.dart';

class OmniboxSuggestionsOverlay extends StatelessWidget {
  final List<OmniboxSuggestion> options;
  final ValueChanged<OmniboxSuggestion> onSelected;

  const OmniboxSuggestionsOverlay({
    super.key,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        color: omniboxSurfaceColor(theme),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(kOmniboxFieldRadius),
          bottomRight: Radius.circular(kOmniboxFieldRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 320),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            itemCount: options.length,
            separatorBuilder: (context, index) {
              return Divider(
                height: 1,
                color: theme.colorScheme.outline.withAlpha(50),
              );
            },
            itemBuilder: (context, index) {
              final option = options[index];
              return OmniboxSuggestionRow(
                option: option,
                onTap: () => onSelected(option),
              );
            },
          ),
        ),
      ),
    );
  }
}

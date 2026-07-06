import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_style.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_suggestions_overlay.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_url_text.dart';
import 'package:flutterbird/features/browser/state/omnibox_state.dart';
import 'package:ladybird/ladybird.dart';

/// The URL/search input in the desktop omnibox toolbar. Navigation is fully
/// delegated to the parent via [onSubmitted] and [onSuggestionSelected]
/// since the parent owns the per-tab text-sync state that a committed
/// navigation needs to update.
class OmniboxSearchField extends ConsumerWidget {
  final LadybirdController currentTabController;
  final TextEditingController omniBoxTextController;
  final FocusNode omniboxFocusNode;
  final BrowserOmnibox omniboxController;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<OmniboxSuggestion> onSuggestionSelected;

  const OmniboxSearchField({
    super.key,
    required this.currentTabController,
    required this.omniBoxTextController,
    required this.omniboxFocusNode,
    required this.omniboxController,
    required this.onSubmitted,
    required this.onSuggestionSelected,
  });

  Widget _buildOverlayText(ThemeData theme, String text) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(
              styledUrlSpan(theme, text),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: StrutStyle.fromTextStyle(theme.textTheme.bodyMedium!),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<String>(
      valueListenable: currentTabController.urlNotifier,
      builder: (context, url, child) {
        return RawAutocomplete<OmniboxSuggestion>(
          textEditingController: omniBoxTextController,
          focusNode: omniboxFocusNode,
          displayStringForOption: (option) => option.value,
          optionsBuilder: (textEditingValue) {
            return omniboxController.suggestionsFor(
              currentTabController,
              textEditingValue.text,
            );
          },
          onSelected: onSuggestionSelected,
          fieldViewBuilder:
              (context, textEditingController, focusNode, onFieldSubmitted) {
                return ValueListenableBuilder<TextEditingValue>(
                  valueListenable: textEditingController,
                  builder: (context, editingValue, child) {
                    final isFocused = focusNode.hasFocus;

                    final fieldRadius = BorderRadius.circular(
                      kOmniboxFieldRadius,
                    );
                    return Stack(
                      children: [
                        TextField(
                          onSubmitted: (value) {
                            onSubmitted(value);
                            onFieldSubmitted();
                          },
                          controller: textEditingController,
                          focusNode: focusNode,
                          style: theme.textTheme.bodyMedium!.copyWith(
                            fontSize: 13,
                            color: isFocused
                                ? theme.colorScheme.onSurface
                                : Colors.transparent,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: omniboxSurfaceColor(theme),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            hintStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(150),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: fieldRadius,
                              borderSide: BorderSide(
                                color: theme.colorScheme.surface,
                                width: 0,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: fieldRadius,
                              borderSide: BorderSide(
                                color: theme.colorScheme.primary,
                                width: 0,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: fieldRadius,
                              borderSide: BorderSide(
                                color: theme.colorScheme.error,
                                width: 1,
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: fieldRadius,
                              borderSide: BorderSide(
                                color: theme.colorScheme.error,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                        if (!isFocused)
                          _buildOverlayText(theme, editingValue.text),
                      ],
                    );
                  },
                );
              },
          optionsViewBuilder: (context, onSelected, options) {
            return Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: OmniboxSuggestionsOverlay(
                options: options.toList(growable: false),
                onSelected: onSelected,
              ),
            );
          },
        );
      },
    );
  }
}

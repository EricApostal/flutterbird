import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/state/omnibox_state.dart';
import 'package:ladybird/ladybird.dart';

class BrowserOmniboxBar extends ConsumerStatefulWidget {
  final LadybirdController currentTabController;

  const BrowserOmniboxBar({required this.currentTabController, super.key});

  @override
  ConsumerState<BrowserOmniboxBar> createState() => _BrowserOmniboxBarState();
}

class _BrowserOmniboxBarState extends ConsumerState<BrowserOmniboxBar> {
  static const double _kBookmarkItemWidth = 170;
  static const double _kBookmarkOverflowButtonWidth = 40;

  final FocusNode _omniboxFocusNode = FocusNode();
  LadybirdController? _trackedTabController;
  bool _suppressTrackedTextSync = false;

  @override
  void initState() {
    super.initState();
    _syncTrackedTabController(widget.currentTabController);
  }

  @override
  void didUpdateWidget(covariant BrowserOmniboxBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTabController != widget.currentTabController) {
      _syncTrackedTabController(widget.currentTabController);
    }
  }

  @override
  void dispose() {
    _syncTrackedTabController(null);
    _omniboxFocusNode.dispose();
    super.dispose();
  }

  void _syncTrackedTabController(LadybirdController? controller) {
    if (_trackedTabController == controller) return;

    _trackedTabController?.urlNotifier.removeListener(_onTrackedUrlChanged);
    _trackedTabController?.textController.removeListener(_onTrackedTextChanged);
    _trackedTabController = controller;

    if (controller == null) return;

    controller.urlNotifier.addListener(_onTrackedUrlChanged);
    controller.textController.addListener(_onTrackedTextChanged);
    _scheduleSyncEngineOmnibox(
      controller,
      refreshBookmarks: true,
      refreshHistory: true,
    );
  }

  void _onTrackedUrlChanged() {
    final controller = _trackedTabController;
    if (controller == null) return;
    _scheduleSyncEngineOmnibox(
      controller,
      refreshBookmarks: true,
      refreshHistory: true,
    );
  }

  void _onTrackedTextChanged() {
    if (_suppressTrackedTextSync) return;
    final controller = _trackedTabController;
    if (controller == null) return;
    _scheduleSyncEngineOmnibox(
      controller,
      refreshBookmarks: false,
      refreshHistory: true,
    );
  }

  void _scheduleSyncEngineOmnibox(
    LadybirdController controller, {
    required bool refreshBookmarks,
    required bool refreshHistory,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _trackedTabController != controller) return;
      final omnibox = ref.read(browserOmniboxProvider.notifier);
      if (refreshBookmarks) {
        omnibox.refreshBookmarksFromEngine(controller);
      }
      if (refreshHistory) {
        omnibox.refreshHistorySuggestionsFromEngine(
          controller,
          controller.textController.text,
        );
      }
    });
  }

  Widget _faviconOrIcon({
    required String? favicon,
    required IconData fallback,
    required double size,
    Color? color,
  }) {
    if (favicon == null || favicon.isEmpty) {
      return Icon(fallback, size: size, color: color);
    }

    if (favicon.startsWith('http://') || favicon.startsWith('https://')) {
      return Image.network(
        favicon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Icon(fallback, size: size, color: color);
        },
      );
    }

    try {
      final base64Payload = favicon.startsWith('data:')
          ? favicon.substring(favicon.indexOf(',') + 1)
          : favicon;
      final bytes = base64Decode(base64Payload);
      if (bytes.isEmpty) {
        return Icon(fallback, size: size, color: color);
      }

      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Icon(fallback, size: size, color: color);
        },
      );
    } catch (_) {
      return Icon(fallback, size: size, color: color);
    }
  }

  void _openBookmark(LadybirdController currentTabController, String url) {
    currentTabController.navigate(url);
  }

  Widget _buildBookmarksToolbar(
    ThemeData theme,
    List<BrowserBookmark> bookmarks,
    LadybirdController currentTabController,
  ) {
    if (bookmarks.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        var visibleCount = (maxWidth / _kBookmarkItemWidth).floor();
        if (visibleCount < 0) visibleCount = 0;
        if (visibleCount > bookmarks.length) visibleCount = bookmarks.length;

        if (bookmarks.length > visibleCount) {
          final adjustedCount =
              ((maxWidth - _kBookmarkOverflowButtonWidth) / _kBookmarkItemWidth)
                  .floor();
          visibleCount = adjustedCount.clamp(0, bookmarks.length);
        }

        final visible = bookmarks.take(visibleCount).toList(growable: false);
        final overflow = bookmarks.skip(visibleCount).toList(growable: false);

        return Row(
          children: [
            for (final bookmark in visible)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: _kBookmarkItemWidth - 6,
                  child: Tooltip(
                    message: bookmark.url,
                    child: OutlinedButton(
                      onPressed: () {
                        _openBookmark(currentTabController, bookmark.url);
                      },
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        side: BorderSide(width: 0, color: Colors.transparent),
                      ),
                      child: Row(
                        children: [
                          _faviconOrIcon(
                            favicon: bookmark.favicon,
                            fallback: Icons.bookmark,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              bookmark.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (overflow.isNotEmpty)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 20),
                tooltip: 'More bookmarks',
                onSelected: (value) {
                  _openBookmark(currentTabController, value);
                },
                itemBuilder: (context) {
                  return overflow
                      .map((bookmark) {
                        return PopupMenuItem<String>(
                          value: bookmark.url,
                          child: SizedBox(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: .min,
                                  children: [
                                    _faviconOrIcon(
                                      favicon: bookmark.favicon,
                                      fallback: Icons.bookmark,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        bookmark.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  bookmark.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      })
                      .toList(growable: false);
                },
              ),
          ],
        );
      },
    );
  }

  void _submitOmniboxInput(
    BrowserOmnibox omnibox,
    LadybirdController currentTabController,
    String value,
  ) {
    final rawInput = value.trim();
    if (rawInput.isEmpty) return;

    final target = omnibox.buildNavigationTarget(rawInput);
    if (target.isEmpty) return;

    currentTabController.navigate(target);
  }

  void _onSuggestionSelected(
    BrowserOmnibox omnibox,
    LadybirdController currentTabController,
    OmniboxSuggestion suggestion,
  ) {
    final target =
        suggestion.type == OmniboxSuggestionType.searchAction ||
            suggestion.type == OmniboxSuggestionType.searchQuery
        ? omnibox.buildNavigationTarget(suggestion.value)
        : suggestion.value;

    if (target.isEmpty) return;

    currentTabController.navigate(target);
  }

  IconData _suggestionIconFor(OmniboxSuggestionType type) {
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

  Widget _suggestionLeading(ThemeData theme, OmniboxSuggestion option) {
    final fallback = _suggestionIconFor(option.type);
    return _faviconOrIcon(
      favicon: option.favicon,
      fallback: fallback,
      size: 18,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  InputDecoration _buildInputDecoration() {
    final theme = Theme.of(context);
    final radius = 8.0;

    return InputDecoration(
      hintText: 'Search',
      filled: true,
      fillColor: theme.colorScheme.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      hintStyle: theme.textTheme.bodyMedium!.copyWith(
        color: theme.colorScheme.onSurface.withAlpha(150),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.surface, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final omniboxController = ref.read(browserOmniboxProvider.notifier);
    final bookmarks = ref.watch(
      browserOmniboxProvider.select((value) => value.bookmarks),
    );
    final currentTabController = widget.currentTabController;

    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4, top: 4),
        child: Column(
          children: [
            Row(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: currentTabController.canGoBackNotifier,
                  builder: (context, canGoBack, child) {
                    return IconButton(
                      icon: const Icon(Icons.arrow_back, size: 20),
                      onPressed: canGoBack
                          ? () {
                              currentTabController.goBack();
                            }
                          : null,
                      splashRadius: 20,
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: currentTabController.canGoForwardNotifier,
                  builder: (context, canGoForward, child) {
                    return IconButton(
                      icon: const Icon(Icons.arrow_forward, size: 20),
                      onPressed: canGoForward
                          ? () {
                              currentTabController.goForward();
                            }
                          : null,
                      splashRadius: 20,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () {
                    currentTabController.reload();
                  },
                  splashRadius: 20,
                ),
                ValueListenableBuilder<String>(
                  valueListenable: currentTabController.urlNotifier,
                  builder: (context, url, child) {
                    final normalized = omniboxController.normalizeUrl(url);
                    final isBookmarked = currentTabController
                        .isCurrentViewBookmarked();
                    return IconButton(
                      icon: Icon(
                        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                        size: 20,
                      ),
                      tooltip: isBookmarked
                          ? 'Remove bookmark'
                          : 'Add bookmark',
                      onPressed: normalized.isEmpty
                          ? null
                          : () {
                              omniboxController.toggleBookmarkForCurrentView(
                                currentTabController,
                              );
                            },
                      splashRadius: 20,
                    );
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: currentTabController.urlNotifier,
                    builder: (context, url, child) {
                      if (currentTabController.textController.text != url &&
                          !_omniboxFocusNode.hasFocus) {
                        _suppressTrackedTextSync = true;
                        currentTabController.textController.text = url;
                        _suppressTrackedTextSync = false;
                      }

                      return RawAutocomplete<OmniboxSuggestion>(
                        textEditingController:
                            currentTabController.textController,
                        focusNode: _omniboxFocusNode,
                        displayStringForOption: (option) => option.value,
                        optionsBuilder: (textEditingValue) {
                          return omniboxController.suggestionsFor(
                            textEditingValue.text,
                          );
                        },
                        onSelected: (suggestion) {
                          _onSuggestionSelected(
                            omniboxController,
                            currentTabController,
                            suggestion,
                          );
                        },
                        fieldViewBuilder:
                            (
                              context,
                              textEditingController,
                              focusNode,
                              onFieldSubmitted,
                            ) {
                              return TextField(
                                onSubmitted: (value) {
                                  _submitOmniboxInput(
                                    omniboxController,
                                    currentTabController,
                                    value,
                                  );
                                  onFieldSubmitted();
                                },
                                controller: textEditingController,
                                focusNode: focusNode,
                                decoration: _buildInputDecoration(),
                                style: theme.textTheme.bodyMedium!,
                              );
                            },
                        optionsViewBuilder: (context, onSelected, options) {
                          final optionList = options.toList(growable: false);
                          if (optionList.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 6,
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 760,
                                  maxHeight: 320,
                                ),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  shrinkWrap: true,
                                  itemCount: optionList.length,
                                  separatorBuilder: (context, index) {
                                    return Divider(
                                      height: 1,
                                      color: theme.colorScheme.outline
                                          .withAlpha(50),
                                    );
                                  },
                                  itemBuilder: (context, index) {
                                    final option = optionList[index];
                                    return InkWell(
                                      onTap: () => onSelected(option),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            _suggestionLeading(theme, option),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    option.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  if (option.subtitle != null)
                                                    Text(
                                                      option.subtitle!,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: theme
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: theme
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            if (bookmarks.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                width: double.infinity,
                child: _buildBookmarksToolbar(
                  theme,
                  bookmarks,
                  currentTabController,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

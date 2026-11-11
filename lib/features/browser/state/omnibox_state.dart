import 'dart:convert';

import 'package:bird_core/bird_core.dart';
import 'package:ladybird/ladybird.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'omnibox_state.g.dart';

enum OmniboxSuggestionType { bookmark, history, searchQuery, searchAction }

class OmniboxSuggestion {
  final OmniboxSuggestionType type;
  final String title;
  final String value;
  final String? subtitle;
  final String? favicon;

  const OmniboxSuggestion({
    required this.type,
    required this.title,
    required this.value,
    this.subtitle,
    this.favicon,
  });
}

class BrowserOmniboxState {
  final List<BirdBookmark> bookmarks;
  final List<OmniboxSuggestion> historySuggestions;

  const BrowserOmniboxState({
    this.bookmarks = const [],
    this.historySuggestions = const [],
  });

  BrowserOmniboxState copyWith({
    List<BirdBookmark>? bookmarks,
    List<OmniboxSuggestion>? historySuggestions,
  }) {
    return BrowserOmniboxState(
      bookmarks: bookmarks ?? this.bookmarks,
      historySuggestions: historySuggestions ?? this.historySuggestions,
    );
  }
}

@Riverpod(keepAlive: true)
class BrowserOmnibox extends _$BrowserOmnibox {
  @override
  BrowserOmniboxState build() {
    return const BrowserOmniboxState();
  }

  String searchEngineLabel(LadybirdController controller) =>
      controller.activeSearchEngine.name;

  bool isDefaultSearchHome(LadybirdController controller, String inputUrl) {
    final value = inputUrl.trim();
    if (value.isEmpty) return false;

    final parsed = Uri.tryParse(value);
    if (parsed == null || !parsed.hasScheme) return false;

    final searchEngineHost = Uri.tryParse(
      controller.activeSearchEngine.queryUrl,
    )?.host.toLowerCase();
    if (searchEngineHost == null || searchEngineHost.isEmpty) return false;

    final host = parsed.host.toLowerCase();
    final isDefaultHost =
        host == searchEngineHost || host == 'www.$searchEngineHost';
    if (!isDefaultHost) return false;

    // Search engine home pages redirect to the same root URL with tracking or
    // cache-busting parameters (Google appends "?zx=..."). Those are still the
    // untouched new-tab page, not a destination the omnibox should reveal.
    return parsed.path.isEmpty || parsed.path == '/';
  }

  // True while [url] is still a new tab's untouched page: the initial
  // about:blank document, or the configured search engine's home page
  // (including a redirect that adds query parameters).
  bool isUntouchedNewTabUrl(LadybirdController controller, String url) {
    final value = url.trim();
    if (value.isEmpty || value == 'about:blank') return true;
    return isDefaultSearchHome(controller, value);
  }

  String normalizeUrl(String input) {
    final value = input.trim();
    if (value.isEmpty) return '';

    final parsed = Uri.tryParse(value);
    if (parsed == null) return value;
    if (parsed.hasScheme) return parsed.toString();
    return 'https://$value';
  }

  bool isLikelyUrl(String input) {
    final value = input.trim();
    if (value.isEmpty) return false;

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return true;

    return value.contains('.') && !value.contains(' ');
  }

  String buildNavigationTarget(LadybirdController controller, String input) {
    final value = input.trim();
    if (value.isEmpty) return '';

    if (isLikelyUrl(value)) {
      return normalizeUrl(value);
    }

    final engine = controller.activeSearchEngine;
    return engine.queryUrl.replaceAll('%s', Uri.encodeQueryComponent(value));
  }

  bool isBookmarked(String url) {
    if (url.trim().isEmpty) return false;
    final normalized = normalizeUrl(url);
    return state.bookmarks.any((bookmark) => bookmark.url == normalized);
  }

  void refreshBookmarks(LadybirdController controller) {
    final bookmarks = ref
        .read(bookmarkStoreProvider)
        .bookmarks(
          directory: controller.getProfileConfigDirectory(),
          faviconPng: controller.getFaviconPngBase64,
        );
    state = state.copyWith(bookmarks: bookmarks);
  }

  void refreshHistorySuggestionsFromEngine(
    LadybirdController controller,
    String query,
  ) {
    final rawJson = controller.getHistoryAutocompleteJson(query, limit: 8);
    final historySuggestions = _parseHistorySuggestionsJson(rawJson);
    state = state.copyWith(historySuggestions: historySuggestions);
  }

  void toggleBookmarkForCurrentView(LadybirdController controller) {
    ref
        .read(bookmarkStoreProvider)
        .toggle(
          directory: controller.getProfileConfigDirectory(),
          url: controller.urlNotifier.value,
          title: controller.titleNotifier.value,
          faviconHash: controller.getViewFaviconHash(),
        );
    refreshBookmarks(controller);
  }

  String? _readFavicon(Map<String, dynamic> item) {
    final candidates = [
      item['favicon'],
      item['favicon_base64_png'],
      item['icon'],
      item['icon_url'],
    ];

    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }

    return null;
  }

  List<OmniboxSuggestion> _parseHistorySuggestionsJson(String rawJson) {
    if (rawJson.trim().isEmpty) return const [];

    final decoded = jsonDecode(rawJson);
    if (decoded is! List<dynamic>) return const [];

    final items = <OmniboxSuggestion>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final rawUrl = entry['url'];
      if (rawUrl is! String || rawUrl.trim().isEmpty) continue;

      final rawTitle = entry['title'];
      final title = (rawTitle is String && rawTitle.trim().isNotEmpty)
          ? rawTitle.trim()
          : rawUrl;

      items.add(
        OmniboxSuggestion(
          type: OmniboxSuggestionType.history,
          title: title,
          value: rawUrl,
          subtitle: rawUrl,
          favicon: _readFavicon(entry),
        ),
      );
    }

    return items;
  }

  Iterable<OmniboxSuggestion> suggestionsFor(
    LadybirdController controller,
    String input,
  ) {
    final query = input.trim();
    final queryLower = query.toLowerCase();

    final items = <OmniboxSuggestion>[];

    if (query.isNotEmpty && !isLikelyUrl(query)) {
      items.add(
        OmniboxSuggestion(
          type: OmniboxSuggestionType.searchAction,
          title: 'Search ${searchEngineLabel(controller)} for "$query"',
          value: query,
          subtitle: 'Search suggestion',
        ),
      );
    }

    for (final bookmark in state.bookmarks) {
      if (query.isNotEmpty &&
          !bookmark.title.toLowerCase().contains(queryLower) &&
          !bookmark.url.toLowerCase().contains(queryLower)) {
        continue;
      }

      items.add(
        OmniboxSuggestion(
          type: OmniboxSuggestionType.bookmark,
          title: bookmark.title,
          value: bookmark.url,
          subtitle: bookmark.url,
          favicon: bookmark.favicon,
        ),
      );
    }

    for (final suggestion in state.historySuggestions) {
      if (query.isNotEmpty &&
          !suggestion.title.toLowerCase().contains(queryLower) &&
          !suggestion.value.toLowerCase().contains(queryLower)) {
        continue;
      }
      items.add(suggestion);
    }

    final deduped = <String>{};
    final limited = <OmniboxSuggestion>[];

    for (final item in items) {
      final key = '${item.type}:${item.value}';
      if (deduped.add(key)) {
        limited.add(item);
      }
      if (limited.length >= 8) break;
    }

    return limited;
  }
}

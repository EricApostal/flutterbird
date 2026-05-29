import 'dart:convert';

import 'package:ladybird/ladybird.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'omnibox_state.g.dart';

enum OmniboxSuggestionType { bookmark, history, searchQuery, searchAction }

class BrowserBookmark {
  final String url;
  final String title;
  final String? favicon;

  const BrowserBookmark({required this.url, required this.title, this.favicon});
}

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
  final List<BrowserBookmark> bookmarks;
  final List<OmniboxSuggestion> historySuggestions;

  const BrowserOmniboxState({
    this.bookmarks = const [],
    this.historySuggestions = const [],
  });

  BrowserOmniboxState copyWith({
    List<BrowserBookmark>? bookmarks,
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
  static const String defaultSearchEngineLabel = 'DuckDuckGo';
  static const String _defaultSearchEngineHost = 'duckduckgo.com';
  static const String _defaultSearchEngineUrl =
      'https://$_defaultSearchEngineHost/';

  @override
  BrowserOmniboxState build() {
    return const BrowserOmniboxState();
  }

  bool isDefaultSearchHome(String inputUrl) {
    final value = inputUrl.trim();
    if (value.isEmpty) return false;

    final parsed = Uri.tryParse(value);
    if (parsed == null || !parsed.hasScheme) return false;

    final host = parsed.host.toLowerCase();
    final isDefaultHost =
        host == _defaultSearchEngineHost ||
        host == 'www.$_defaultSearchEngineHost';
    if (!isDefaultHost) return false;

    final hasRootPath = parsed.path.isEmpty || parsed.path == '/';
    return hasRootPath && parsed.query.isEmpty && parsed.fragment.isEmpty;
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

  String buildNavigationTarget(String input) {
    final value = input.trim();
    if (value.isEmpty) return '';

    if (isLikelyUrl(value)) {
      return normalizeUrl(value);
    }

    final query = Uri.encodeQueryComponent(value);
    return '$_defaultSearchEngineUrl?q=$query';
  }

  bool isBookmarked(String url) {
    if (url.trim().isEmpty) return false;
    final normalized = normalizeUrl(url);
    return state.bookmarks.any((bookmark) => bookmark.url == normalized);
  }

  void refreshBookmarksFromEngine(LadybirdController controller) {
    final rawJson = controller.getBookmarksJson();
    final bookmarks = _parseBookmarksJson(rawJson);
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
    controller.toggleBookmarkForCurrentView();
    refreshBookmarksFromEngine(controller);
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

  List<BrowserBookmark> _parseBookmarksJson(String rawJson) {
    if (rawJson.trim().isEmpty) return const [];

    final decoded = jsonDecode(rawJson);
    if (decoded is! List<dynamic>) return const [];

    final bookmarks = <BrowserBookmark>[];

    void collect(dynamic item) {
      if (item is! Map<String, dynamic>) return;
      final type = item['type'];
      if (type == 'bookmark') {
        final rawUrl = item['url'];
        if (rawUrl is! String || rawUrl.trim().isEmpty) return;
        final rawTitle = item['title'];
        final title = (rawTitle is String && rawTitle.trim().isNotEmpty)
            ? rawTitle.trim()
            : rawUrl;
        bookmarks.add(
          BrowserBookmark(
            url: rawUrl,
            title: title,
            favicon: _readFavicon(item),
          ),
        );
        return;
      }

      if (type == 'folder') {
        final children = item['children'];
        if (children is! List<dynamic>) return;
        for (final child in children) {
          if (child is Map<String, dynamic>) collect(child);
        }
      }
    }

    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        collect(item);
      }
    }

    return bookmarks;
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

  Iterable<OmniboxSuggestion> suggestionsFor(String input) {
    final query = input.trim();
    final queryLower = query.toLowerCase();

    final items = <OmniboxSuggestion>[];

    if (query.isNotEmpty && !isLikelyUrl(query)) {
      items.add(
        OmniboxSuggestion(
          type: OmniboxSuggestionType.searchAction,
          title: 'Search $defaultSearchEngineLabel for "$query"',
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

/// What the new tab page shows, worked out from the history.
library;

import 'dart:convert';

/// The address of the new tab page. The engine has a plain page of its own
/// there, which the browser's own is shown over.
const String kNewTabUrl = 'about:newtab';

/// A page in the history.
class VisitedPage {
  const VisitedPage({
    required this.url,
    required this.lastVisited,
    this.title = '',
    this.visitCount = 1,
    this.favicon,
  });

  final String url;
  final String title;
  final int visitCount;
  final DateTime lastVisited;

  /// A base64 PNG, when the engine has one.
  final String? favicon;
}

/// The pages in the history as the engine lists them (`history_entries_json`).
/// Whatever cannot be read is left out.
List<VisitedPage> parseVisitedPages(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];

  final pages = <VisitedPage>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final url = item['url'];
    final lastVisited = item['lastVisited'];
    if (url is! String || url.isEmpty || lastVisited is! int) continue;
    final title = item['title'];
    final visits = item['visitCount'];
    final favicon = item['favicon'];
    pages.add(
      VisitedPage(
        url: url,
        title: title is String ? title : '',
        visitCount: visits is int ? visits : 1,
        lastVisited: DateTime.fromMillisecondsSinceEpoch(lastVisited),
        favicon: favicon is String ? favicon : null,
      ),
    );
  }
  return pages;
}

/// A site gone to often enough to be offered.
class FrequentSite {
  const FrequentSite({
    required this.host,
    required this.url,
    required this.score,
    this.favicon,
  });

  /// Without a leading `www.`, which is also what it is called.
  final String host;

  /// The site's front page.
  final String url;
  final int score;
  final String? favicon;
}

/// The host of a web address without a leading `www.`, or '' for anything
/// else.
String siteHost(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return '';
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Whether [url] is the results of a search, which is a way to somewhere
/// rather than somewhere to go back to.
bool isSearchResultsPage(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final Map<String, List<String>> query;
  try {
    query = uri.queryParametersAll;
  } on FormatException {
    return false;
  } on ArgumentError {
    // Percent-encoding that is not UTF-8.
    return false;
  }
  if (query.containsKey('search_query')) return true;
  if (!query.containsKey('q') && !query.containsKey('query')) return false;
  // `/search?q=`, `/results?q=`, and the front page that searches, `/?q=`.
  final path = uri.path;
  return path.isEmpty ||
      path == '/' ||
      path.contains('search') ||
      path.startsWith('/results');
}

// How much a visit counts by how long ago the page was last seen, in the steps
// Firefox's frecency uses.
int _recencyWeight(Duration age) {
  if (age.inDays <= 4) return 100;
  if (age.inDays <= 14) return 70;
  if (age.inDays <= 31) return 50;
  if (age.inDays <= 90) return 30;
  return 10;
}

// A page reloaded all day must not outweigh a site gone to all month.
const int _mostVisitsCounted = 50;

/// The sites gone to most, favouring those gone to lately. Pages are counted
/// by site, and each site is offered as its front page. Sites in [hidden] are
/// left out.
List<FrequentSite> frequentSites(
  Iterable<VisitedPage> pages, {
  required DateTime now,
  Set<String> hidden = const {},
  int limit = 8,
}) {
  final scores = <String, int>{};
  final best = <String, (int, Uri)>{};
  final icons = <String, (int, String)>{};
  final frontPages = <String, Uri>{};

  for (final page in pages) {
    final host = siteHost(page.url);
    if (host.isEmpty || hidden.contains(host)) continue;
    if (isSearchResultsPage(page.url)) continue;

    final uri = Uri.parse(page.url);
    final score =
        page.visitCount.clamp(1, _mostVisitsCounted) *
        _recencyWeight(now.difference(page.lastVisited));
    scores[host] = (scores[host] ?? 0) + score;

    if (score > (best[host]?.$1 ?? -1)) best[host] = (score, uri);
    final favicon = page.favicon;
    if (favicon != null &&
        favicon.isNotEmpty &&
        score > (icons[host]?.$1 ?? -1)) {
      icons[host] = (score, favicon);
    }
    if ((uri.path.isEmpty || uri.path == '/') && !uri.hasQuery) {
      if (frontPages[host]?.scheme != 'https') frontPages[host] = uri;
    }
  }

  final ranked = scores.keys.toList()
    ..sort((a, b) {
      final byScore = scores[b]!.compareTo(scores[a]!);
      return byScore != 0 ? byScore : a.compareTo(b);
    });

  return [
    for (final host in ranked.take(limit))
      FrequentSite(
        host: host,
        url: _frontPage(frontPages[host] ?? best[host]!.$2),
        score: scores[host]!,
        favicon: icons[host]?.$2,
      ),
  ];
}

// The front page of the site [from] is on, spelled the way it was visited.
String _frontPage(Uri from) => Uri(
  scheme: from.scheme,
  host: from.host,
  port: from.hasPort ? from.port : null,
  path: '/',
).toString();

/// The pages seen last, newest first: web pages other than searches, one for
/// each address, and one for each title on a site.
List<VisitedPage> recentPages(Iterable<VisitedPage> pages, {int limit = 6}) {
  final newest = pages.toList()
    ..sort((a, b) => b.lastVisited.compareTo(a.lastVisited));
  final addresses = <String>{};
  final titles = <(String, String)>{};
  final result = <VisitedPage>[];

  for (final page in newest) {
    if (result.length >= limit) break;
    final host = siteHost(page.url);
    if (host.isEmpty || isSearchResultsPage(page.url)) continue;
    final hash = page.url.indexOf('#');
    if (!addresses.add(hash < 0 ? page.url : page.url.substring(0, hash))) {
      continue;
    }
    final title = page.title.trim();
    if (title.isNotEmpty && !titles.add((host, title))) continue;
    result.add(page);
  }
  return result;
}

String greetingFor(DateTime time) {
  if (time.hour >= 5 && time.hour < 12) return 'Good morning';
  if (time.hour >= 12 && time.hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// `9:05` or `21:05`.
String clockText(DateTime time, {required bool use24Hour}) {
  final minute = time.minute.toString().padLeft(2, '0');
  if (use24Hour) return '${time.hour.toString().padLeft(2, '0')}:$minute';
  final hour = time.hour % 12;
  return '${hour == 0 ? 12 : hour}:$minute';
}

const List<String> _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', //
  'September', 'October', 'November', 'December',
];

/// `Thursday, November 26`.
String longDateText(DateTime date) =>
    '${_weekdays[date.weekday - 1]}, ${_months[date.month - 1]} ${date.day}';

/// How long ago [then] was, in a few characters.
String timeAgo(DateTime then, DateTime now) {
  final age = now.difference(then);
  if (age.inMinutes < 1) return 'now';
  if (age.inMinutes < 60) return '${age.inMinutes}m';
  if (age.inHours < 24) return '${age.inHours}h';
  if (age.inDays < 7) return '${age.inDays}d';
  if (age.inDays < 365) return '${age.inDays ~/ 7}w';
  return '${age.inDays ~/ 365}y';
}

/// What the user chose to have on the new tab page.
class NewTabSettings {
  const NewTabSettings({
    this.showClock = true,
    this.showBookmarks = true,
    this.showFrequentSites = true,
    this.showRecent = true,
    this.showRecentlyClosed = true,
    this.hiddenSites = const {},
  });

  /// Anything missing or of the wrong kind is as it was to begin with.
  factory NewTabSettings.fromJson(Object? json) {
    if (json is! Map) return const NewTabSettings();
    bool on(String key) => json[key] != false;
    final hidden = json['hiddenSites'];
    return NewTabSettings(
      showClock: on('showClock'),
      showBookmarks: on('showBookmarks'),
      showFrequentSites: on('showFrequentSites'),
      showRecent: on('showRecent'),
      showRecentlyClosed: on('showRecentlyClosed'),
      hiddenSites: hidden is List ? hidden.whereType<String>().toSet() : const {},
    );
  }

  final bool showClock;
  final bool showBookmarks;
  final bool showFrequentSites;
  final bool showRecent;
  final bool showRecentlyClosed;

  /// Hosts the user took out of the frequently visited sites.
  final Set<String> hiddenSites;

  Map<String, Object?> toJson() => {
    'showClock': showClock,
    'showBookmarks': showBookmarks,
    'showFrequentSites': showFrequentSites,
    'showRecent': showRecent,
    'showRecentlyClosed': showRecentlyClosed,
    'hiddenSites': hiddenSites.toList()..sort(),
  };

  NewTabSettings copyWith({
    bool? showClock,
    bool? showBookmarks,
    bool? showFrequentSites,
    bool? showRecent,
    bool? showRecentlyClosed,
    Set<String>? hiddenSites,
  }) => NewTabSettings(
    showClock: showClock ?? this.showClock,
    showBookmarks: showBookmarks ?? this.showBookmarks,
    showFrequentSites: showFrequentSites ?? this.showFrequentSites,
    showRecent: showRecent ?? this.showRecent,
    showRecentlyClosed: showRecentlyClosed ?? this.showRecentlyClosed,
    hiddenSites: hiddenSites ?? this.hiddenSites,
  );
}

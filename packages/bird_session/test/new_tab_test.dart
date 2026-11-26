import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 26, 15, 30);

  VisitedPage page(
    String url, {
    int visits = 1,
    Duration ago = Duration.zero,
    String title = '',
    String? favicon,
  }) => VisitedPage(
    url: url,
    visitCount: visits,
    lastVisited: now.subtract(ago),
    title: title,
    favicon: favicon,
  );

  group('parseVisitedPages', () {
    test('reads what the engine lists and skips what it cannot', () {
      final pages = parseVisitedPages(
        '[{"url":"https://a.test/","title":"A","visitCount":3,'
        '"lastVisited":1000,"favicon":"png"},'
        '{"url":"https://b.test/","lastVisited":2000},'
        '{"url":"","lastVisited":1},{"url":"https://c.test/"},7]',
      );
      expect(pages.map((p) => p.url), ['https://a.test/', 'https://b.test/']);
      expect(pages.first.title, 'A');
      expect(pages.first.visitCount, 3);
      expect(pages.first.favicon, 'png');
      expect(pages.first.lastVisited.millisecondsSinceEpoch, 1000);
      expect(pages.last.visitCount, 1);
    });

    test('is empty for what is not a list', () {
      expect(parseVisitedPages('{}'), isEmpty);
      expect(parseVisitedPages('nonsense'), isEmpty);
    });
  });

  group('siteHost', () {
    test('drops www and ignores what is not the web', () {
      expect(siteHost('https://WWW.Example.com/a'), 'example.com');
      expect(siteHost('http://news.ycombinator.com'), 'news.ycombinator.com');
      expect(siteHost('about:newtab'), '');
      expect(siteHost('file:///tmp/a'), '');
      expect(siteHost('moz-extension://abc/popup.html'), '');
      expect(siteHost('not a url'), '');
    });
  });

  group('isSearchResultsPage', () {
    test('knows the usual shapes of results', () {
      expect(isSearchResultsPage('https://www.google.com/search?q=a'), isTrue);
      expect(isSearchResultsPage('https://duckduckgo.com/?q=a&ia=web'), isTrue);
      expect(
        isSearchResultsPage('https://youtube.com/results?search_query=a'),
        isTrue,
      );
      expect(isSearchResultsPage('https://github.com/search?q=a'), isTrue);
    });

    test('leaves other pages alone', () {
      expect(isSearchResultsPage('https://duckduckgo.com/'), isFalse);
      expect(isSearchResultsPage('https://a.test/watch?v=x'), isFalse);
      expect(isSearchResultsPage('https://a.test/item?q=3'), isFalse);
    });

    test('does not throw on a query that is not UTF-8', () {
      expect(isSearchResultsPage('https://a.test/search?q=%ff'), isFalse);
    });
  });

  group('frequentSites', () {
    test('counts pages by site and offers the front page', () {
      final sites = frequentSites([
        page('https://www.youtube.com/watch?v=1', visits: 3),
        page('https://www.youtube.com/watch?v=2', visits: 3),
        page('https://github.com/a/b', visits: 5),
      ], now: now);
      expect(sites.map((s) => s.host), ['youtube.com', 'github.com']);
      expect(sites.first.url, 'https://www.youtube.com/');
    });

    test('favours what was seen lately', () {
      final sites = frequentSites([
        page('https://old.test/', visits: 20, ago: const Duration(days: 200)),
        page('https://new.test/', visits: 4),
      ], now: now);
      expect(sites.first.host, 'new.test');
    });

    test('is not swamped by one page reloaded forever', () {
      final sites = frequentSites([
        page('https://reloaded.test/', visits: 100000),
        for (var i = 0; i < 60; i++) page('https://used.test/$i'),
      ], now: now);
      expect(sites.first.host, 'used.test');
    });

    test('prefers a visited https front page', () {
      final sites = frequentSites([
        page('http://a.test/', visits: 9),
        page('https://a.test/', visits: 1),
        page('http://a.test/', visits: 1),
      ], now: now);
      expect(sites.single.url, 'https://a.test/');
    });

    test('keeps a port and drops the rest of the address', () {
      final sites = frequentSites([
        page('http://localhost:3000/app/page?x=1#y'),
      ], now: now);
      expect(sites.single.url, 'http://localhost:3000/');
    });

    test('takes an icon from the busiest page that has one', () {
      final sites = frequentSites([
        page('https://a.test/1', visits: 9),
        page('https://a.test/2', visits: 2, favicon: 'two'),
        page('https://a.test/3', visits: 1, favicon: 'three'),
      ], now: now);
      expect(sites.single.favicon, 'two');
    });

    test('leaves out hidden sites, searches and what is not the web', () {
      final sites = frequentSites([
        page('https://hidden.test/', visits: 9),
        page('https://www.google.com/search?q=x', visits: 9),
        page('about:newtab', visits: 9),
        page('https://kept.test/'),
      ], now: now, hidden: {'hidden.test'});
      expect(sites.map((s) => s.host), ['kept.test']);
    });

    test('stops at the limit', () {
      final sites = frequentSites(
        [for (var i = 0; i < 20; i++) page('https://s$i.test/')],
        now: now,
        limit: 8,
      );
      expect(sites, hasLength(8));
    });
  });

  group('recentPages', () {
    test('is newest first, once for each address and title', () {
      final recent = recentPages([
        page('https://a.test/x#one', ago: const Duration(minutes: 3)),
        page('https://a.test/x#two', ago: const Duration(minutes: 1)),
        page('https://a.test/y', title: 'Same', ago: const Duration(minutes: 2)),
        page('https://a.test/z', title: 'Same', ago: const Duration(minutes: 4)),
        page('https://b.test/', title: 'Same', ago: const Duration(minutes: 5)),
        page('https://duckduckgo.com/?q=x'),
        page('about:newtab'),
      ]);
      expect(recent.map((p) => p.url), [
        'https://a.test/x#two',
        'https://a.test/y',
        'https://b.test/',
      ]);
    });
  });

  group('words', () {
    test('greets by the time of day', () {
      String at(int hour) => greetingFor(DateTime(2026, 1, 1, hour));
      expect(at(5), 'Good morning');
      expect(at(11), 'Good morning');
      expect(at(12), 'Good afternoon');
      expect(at(18), 'Good evening');
      expect(at(2), 'Good evening');
    });

    test('tells the time both ways', () {
      expect(clockText(DateTime(2026, 1, 1, 0, 5), use24Hour: false), '12:05');
      expect(clockText(DateTime(2026, 1, 1, 13, 5), use24Hour: false), '1:05');
      expect(clockText(DateTime(2026, 1, 1, 9, 5), use24Hour: true), '09:05');
    });

    test('writes the date', () {
      expect(longDateText(now), 'Thursday, November 26');
    });

    test('says how long ago', () {
      String ago(Duration d) => timeAgo(now.subtract(d), now);
      expect(ago(const Duration(seconds: 20)), 'now');
      expect(ago(const Duration(minutes: 5)), '5m');
      expect(ago(const Duration(hours: 3)), '3h');
      expect(ago(const Duration(days: 2)), '2d');
      expect(ago(const Duration(days: 15)), '2w');
      expect(ago(const Duration(days: 800)), '2y');
    });
  });

  group('NewTabSettings', () {
    test('starts with everything shown', () {
      final settings = NewTabSettings.fromJson(null);
      expect(settings.showClock && settings.showBookmarks, isTrue);
      expect(settings.hiddenSites, isEmpty);
    });

    test('keeps what was chosen', () {
      final saved = const NewTabSettings()
          .copyWith(showRecent: false, hiddenSites: {'b.test', 'a.test'})
          .toJson();
      final read = NewTabSettings.fromJson(saved);
      expect(read.showRecent, isFalse);
      expect(read.showClock, isTrue);
      expect(read.hiddenSites, {'a.test', 'b.test'});
    });

    test('shrugs off nonsense', () {
      final read = NewTabSettings.fromJson({
        'showClock': 'no',
        'hiddenSites': [1, 'a.test'],
      });
      expect(read.showClock, isTrue);
      expect(read.hiddenSites, {'a.test'});
    });
  });
}

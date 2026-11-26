import 'package:bird_session/bird_session.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 26, 15, 30);
  VisitedPage page(String url, DateTime seen, {String title = ''}) =>
      VisitedPage(url: url, lastVisited: seen, title: title);

  test('history is listed by day, the latest first', () {
    final days = historyByDay([
      page('https://old.test/', DateTime(2025, 3, 4, 9)),
      page('https://early.test/', DateTime(2026, 11, 26, 0, 1)),
      page('https://late.test/', DateTime(2026, 11, 26, 15)),
      page('https://yesterday.test/', DateTime(2026, 11, 25, 23, 59)),
      page('https://before.test/', DateTime(2026, 11, 20, 12)),
    ], now: now);

    expect(days.map((day) => day.label), [
      'Today',
      'Yesterday',
      'Friday, November 20',
      'Tuesday, March 4, 2025',
    ]);
    expect(days.first.pages.map((p) => p.url), [
      'https://late.test/',
      'https://early.test/',
    ]);
  });

  test('a search wants every word, in the title or the address', () {
    final pages = [
      page('https://birds.test/owls', now, title: 'Night hunters'),
      page('https://birds.test/gulls', now, title: 'Sea birds'),
    ];
    List<String> found(String query) => [
      for (final day in historyByDay(pages, now: now, query: query))
        for (final p in day.pages) p.url,
    ];
    expect(found('NIGHT owls'), ['https://birds.test/owls']);
    expect(found('birds'), hasLength(2));
    expect(found('owls sea'), isEmpty);
    expect(found('   '), hasLength(2));
  });

  test('sizes read in the largest unit that keeps them above one', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1024), '1 KB');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(12 * 1024 * 1024), '12 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3 GB');
  });
}

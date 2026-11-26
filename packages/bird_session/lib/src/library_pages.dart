/// The small rules of the history and downloads lists.
library;

import 'new_tab.dart';

/// The pages seen on one day.
class HistoryDay {
  const HistoryDay(this.label, this.pages);

  /// `Today`, `Yesterday`, or the date.
  final String label;
  final List<VisitedPage> pages;
}

/// [pages] by the day they were last seen, the latest first. With a [query],
/// only those whose title or address holds every word of it.
List<HistoryDay> historyByDay(
  Iterable<VisitedPage> pages, {
  required DateTime now,
  String query = '',
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final matching = [
    for (final page in pages)
      if (words.every(
        (word) =>
            page.title.toLowerCase().contains(word) ||
            page.url.toLowerCase().contains(word),
      ))
        page,
  ]..sort((a, b) => b.lastVisited.compareTo(a.lastVisited));

  // Days are counted between midnights in UTC, where every day is as long.
  DateTime dayOf(DateTime time) =>
      DateTime.utc(time.year, time.month, time.day);
  final today = dayOf(now);

  final days = <HistoryDay>[];
  DateTime? current;
  for (final page in matching) {
    final day = dayOf(page.lastVisited);
    if (day != current) {
      current = day;
      final age = today.difference(day).inDays;
      final date = longDateText(page.lastVisited);
      days.add(
        HistoryDay(switch (age) {
          <= 0 => 'Today',
          1 => 'Yesterday',
          _ => day.year == today.year ? date : '$date, ${day.year}',
        }, []),
      );
    }
    days.last.pages.add(page);
  }
  return days;
}

/// A size in bytes, as `512 B`, `1.5 KB` or `12 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 10
      ? value.round().toString()
      : value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  return '$text ${units[unit]}';
}

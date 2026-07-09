import 'package:dart_mappable/dart_mappable.dart';

part 'session_history.mapper.dart';

// One entry in Ladybird's own session history mirror for a tab -- the
// authoritative back/forward stack, not a client-side reconstruction of it.
// `step` is the HTML-spec-stable identity for an entry (safe to use as a
// cache key; array position is not, since it can shift under traversal).
@MappableClass()
class LadybirdSessionHistoryEntry with LadybirdSessionHistoryEntryMappable {
  const LadybirdSessionHistoryEntry({
    required this.step,
    required this.url,
    required this.current,
  });

  final int step;
  final String url;
  final bool current;
}

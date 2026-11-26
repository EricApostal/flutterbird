import '../protocol/json.dart';
import 'tool_controller.dart';

class PerfSpan {
  const PerfSpan(this.name, this.type, this.start, this.duration, [this.size = 0]);
  final String name;
  final String type;

  /// Milliseconds from the start of the recording.
  final double start;
  final double duration;
  final int size;
}

class PerfRecording {
  const PerfRecording({
    required this.duration,
    required this.frames,
    required this.spans,
  });

  final double duration;

  /// When each frame began, in milliseconds from the start.
  final List<double> frames;
  final List<PerfSpan> spans;

  /// Frames per second over each [bucket] milliseconds.
  List<double> framesPerSecond([double bucket = 250]) {
    final count = (duration / bucket).ceil().clamp(1, 4000);
    final buckets = List<double>.filled(count, 0);
    for (final frame in frames) {
      final index = (frame ~/ bucket).clamp(0, count - 1);
      buckets[index] += 1000 / bucket;
    }
    return buckets;
  }

  double get averageFps =>
      duration <= 0 ? 0 : frames.length * 1000 / duration;

  /// Stretches over fifty milliseconds in which no frame could be drawn.
  List<PerfSpan> get longFrames => [
    for (var i = 1; i < frames.length; i++)
      if (frames[i] - frames[i - 1] > 50)
        PerfSpan(
          'Long frame',
          'jank',
          frames[i - 1],
          frames[i] - frames[i - 1],
        ),
  ];
}

/// Records what the page can tell about itself: its frames and its timeline
/// entries. The engine has no profiler to give out over DevTools.
class PerformanceController extends ToolController {
  PerformanceController(super.session);

  bool recording = false;
  bool busy = false;
  DateTime? startedAt;
  PerfRecording? result;
  String error = '';

  @override
  void onTargetDestroyed() {
    if (recording) {
      recording = false;
      error = 'The recording ended because the page navigated.';
      changed();
    }
  }

  Future<void> start() async {
    if (recording || busy) return;
    busy = true;
    error = '';
    result = null;
    changed();
    try {
      await session.runInPage(
        'const state = { start: performance.now(), frames: [], running: true };'
        'window.__birdPerformance = state;'
        'const tick = time => { if (!state.running) return; state.frames.push(time - state.start);'
        '  if (state.frames.length < 36000) requestAnimationFrame(tick); };'
        'requestAnimationFrame(tick); return true;',
      );
      recording = true;
      startedAt = DateTime.now();
    } catch (failure) {
      error = '$failure';
    }
    busy = false;
    changed();
  }

  Future<void> stop() async {
    if (!recording || busy) return;
    busy = true;
    changed();
    try {
      final data = await session.runInPage(
        'const state = window.__birdPerformance; if (!state) throw new Error("The recording was lost");'
        'state.running = false; delete window.__birdPerformance;'
        'const end = performance.now();'
        'const spans = performance.getEntries().filter(e => e.startTime + e.duration >= state.start && e.entryType !== "navigation")'
        '  .map(e => ({ name: e.name, type: e.entryType === "resource" ? (e.initiatorType || "resource") : e.entryType,'
        '    start: Math.max(0, e.startTime - state.start), duration: e.duration, size: e.transferSize || 0 }));'
        'return { duration: end - state.start, frames: state.frames, spans };',
      );
      if (data is Map<String, Object?>) {
        result = PerfRecording(
          duration: data.number('duration'),
          frames: [
            for (final frame in data.list('frames'))
              if (frame is num) frame.toDouble(),
          ],
          spans: [
            for (final span in data.maps('spans'))
              PerfSpan(
                span.str('name'),
                span.str('type'),
                span.number('start'),
                span.number('duration'),
                span.integer('size'),
              ),
          ]..sort((a, b) => a.start.compareTo(b.start)),
        );
      }
    } catch (failure) {
      error = '$failure';
    }
    recording = false;
    busy = false;
    changed();
  }

  void discard() {
    result = null;
    error = '';
    changed();
  }
}

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/application_controller.dart';
import '../model/performance_controller.dart';
import '../model/session.dart';
import '../protocol/json.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'network_panel.dart' show formatBytes, formatMillis;

/// The Performance tool. The engine offers no profiler over DevTools, so this
/// records what the page can measure of itself.
class PerformancePanel extends StatelessWidget {
  const PerformancePanel({super.key, required this.session});

  final ToolboxSession session;

  PerformanceController get performance => session.performance;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: performance,
    builder: (context, _) {
      final colors = context.dt;
      final result = performance.result;
      return ColoredBox(
        color: colors.body,
        child: Column(
          children: [
            if (result != null)
              DtToolbar(
                children: [
                  DtButton('New recording', glyph: DtGlyph.record, onPressed: performance.start),
                  const SizedBox(width: 6),
                  DtButton('Discard', glyph: DtGlyph.trash, onPressed: performance.discard),
                ],
              ),
            Expanded(
              child: result != null
                  ? _Recording(result: result)
                  : performance.recording
                  ? DtEmptyState(
                      'Recording…',
                      detail: 'Use the page, then stop the recording to see its frames and timeline.',
                      actions: [DtButton('Stop and show recording', primary: true, glyph: DtGlyph.stop, onPressed: performance.busy ? null : performance.stop)],
                    )
                  : DtEmptyState(
                      'Record the page’s performance',
                      detail:
                          '${performance.error.isEmpty ? '' : '${performance.error}\n\n'}'
                          'Frame rate, long frames, network resources and User Timing marks are recorded from the page. '
                          'The engine does not give DevTools a sampling profiler, so there is no call tree or flame graph.',
                      actions: [DtButton('Start recording', primary: true, glyph: DtGlyph.record, onPressed: performance.busy ? null : performance.start)],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _Recording extends StatelessWidget {
  const _Recording({required this.result});

  final PerfRecording result;

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    final long = result.longFrames;
    Widget stat(String label, String value) => Padding(
      padding: const EdgeInsets.only(right: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.uiStyle(color: colors.textStrong, size: 18, weight: FontWeight.w300)),
          Text(label, style: context.uiStyle(color: colors.textDim, size: 11)),
        ],
      ),
    );
    Widget heading(String text) => Container(
      width: double.infinity,
      color: colors.toolbar,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(text, style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
    );
    final rows = <PerfSpan>[...result.spans, ...long]..sort((a, b) => a.start.compareTo(b.start));
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            runSpacing: 8,
            children: [
              stat('Duration', formatMillis(result.duration)),
              stat('Average FPS', result.averageFps.toStringAsFixed(1)),
              stat('Frames', '${result.frames.length}'),
              stat('Long frames (> 50 ms)', '${long.length}'),
              stat('Longest frame', formatMillis(long.fold<double>(0, (m, s) => math.max(m, s.duration)))),
            ],
          ),
        ),
        heading('Frame rate'),
        SizedBox(
          height: 110,
          child: CustomPaint(
            size: Size.infinite,
            painter: _FrameRatePainter(result.framesPerSecond(), colors, context.uiStyle(size: 10, color: colors.textDim)),
          ),
        ),
        heading('Timeline  (${rows.length} entries)'),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text('Nothing was measured during the recording.', style: context.uiStyle(color: colors.textDim))),
        for (final (index, span) in rows.take(600).indexed)
          Container(
            height: 20,
            color: index.isOdd ? colors.rowAlternate : null,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                SizedBox(width: 66, child: Text(span.type, overflow: TextOverflow.ellipsis, style: context.uiStyle(color: colors.textDim, size: 11))),
                Expanded(flex: 2, child: Text(span.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.uiStyle(color: colors.textStrong, size: 11))),
                Expanded(
                  flex: 3,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = constraints.maxWidth / math.max(result.duration, 1);
                      return Stack(
                        children: [
                          const SizedBox.expand(),
                          Positioned(
                            left: (span.start * scale).clamp(0, constraints.maxWidth - 2),
                            width: (span.duration * scale).clamp(2, constraints.maxWidth),
                            top: 6,
                            height: 8,
                            child: ColoredBox(color: span.type == 'jank' ? const Color(0xFFD70022) : span.type == 'mark' || span.type == 'measure' ? colors.purple : colors.accent),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(width: 70, child: Text(formatMillis(span.duration), textAlign: TextAlign.right, style: context.uiStyle(color: colors.textDim, size: 11))),
                SizedBox(width: 70, child: Text(span.size > 0 ? formatBytes(span.size) : '', textAlign: TextAlign.right, style: context.uiStyle(color: colors.textDim, size: 11))),
              ],
            ),
          ),
      ],
    );
  }
}

class _FrameRatePainter extends CustomPainter {
  _FrameRatePainter(this.values, this.colors, this.style);
  final List<double> values;
  final DtColors colors;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var most = 60.0;
    for (final value in values) {
      most = math.max(most, value);
    }
    const left = 34.0;
    final width = size.width - left - 8;
    final height = size.height - 12;
    for (final fps in [0.0, 30.0, 60.0]) {
      final y = 6 + height - fps / most * height;
      canvas.drawLine(Offset(left, y), Offset(size.width - 8, y), Paint()..color = colors.splitter);
      final painter = TextPainter(text: TextSpan(text: '${fps.round()}', style: style), textDirection: TextDirection.ltr)..layout();
      painter.paint(canvas, Offset(left - painter.width - 4, y - painter.height / 2));
      painter.dispose();
    }
    final path = Path()..moveTo(left, 6 + height);
    for (var i = 0; i < values.length; i++) {
      final x = left + (values.length == 1 ? width : i / (values.length - 1) * width);
      path.lineTo(x, 6 + height - values[i] / most * height);
    }
    final line = Path.from(path);
    path
      ..lineTo(left + width, 6 + height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0x3330A14E));
    canvas.drawPath(line, Paint()..color = const Color(0xFF30A14E)..style = PaintingStyle.stroke..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_FrameRatePainter old) => old.values != values || old.colors != colors;
}

/// The Memory tool, which needs heap snapshots the engine does not offer.
class MemoryPanel extends StatelessWidget {
  const MemoryPanel({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.dt.body,
    child: Column(
      children: [
        const DtToolbar(
          children: [DtButton('Take snapshot', glyph: DtGlyph.memory)],
        ),
        const Expanded(
          child: DtEmptyState(
            'Heap snapshots are not available.',
            detail: 'Ladybird’s DevTools server has no memory actor, so the heap cannot be inspected from here.',
          ),
        ),
      ],
    ),
  );
}

/// The Application tool: service workers and the web app manifest.
class ApplicationPanel extends StatefulWidget {
  const ApplicationPanel({super.key, required this.session});

  final ToolboxSession session;

  @override
  State<ApplicationPanel> createState() => _ApplicationPanelState();
}

class _ApplicationPanelState extends State<ApplicationPanel> {
  ApplicationController get application => widget.session.application;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) application.activate();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: application,
    builder: (context, _) {
      final colors = context.dt;
      Widget section(String id, String label, DtGlyph glyph) => DtHover(
        onTap: () => application.select(id),
        builder: (context, hovered) {
          final selected = application.selected == id;
          return Container(
            height: 30,
            color: selected ? colors.selection : hovered ? colors.rowHover : null,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                DtIcon(glyph, size: 15, color: selected ? colors.selectionText : colors.textDim),
                const SizedBox(width: 8),
                Text(label, style: context.uiStyle(color: selected ? colors.selectionText : colors.text)),
              ],
            ),
          );
        },
      );
      return ColoredBox(
        color: colors.body,
        child: DtSplit(
          sizeSecond: false,
          initialSize: 200,
          minSize: 140,
          first: ColoredBox(
            color: colors.sidebar,
            child: Column(
              children: [
                const SizedBox(height: 4),
                section('workers', 'Service Workers', DtGlyph.gear),
                section('manifest', 'Manifest', DtGlyph.file),
              ],
            ),
          ),
          second: Column(
            children: [
              DtToolbar(
                children: [
                  const Spacer(),
                  DtIconButton(DtGlyph.reload, iconSize: 12, tooltip: 'Refresh', onPressed: application.refresh),
                ],
              ),
              Expanded(child: application.selected == 'manifest' ? _manifest(context) : _workers(context)),
            ],
          ),
        ),
      );
    },
  );

  Widget _workers(BuildContext context) {
    final colors = context.dt;
    if (application.workers.isEmpty) {
      return DtEmptyState(application.loading ? 'Loading…' : 'No service workers found for this page.');
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final worker in application.workers)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: colors.splitter), borderRadius: BorderRadius.circular(3)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(worker.scope, style: context.uiStyle(color: colors.textStrong, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Source: ${worker.scriptUrl}', style: context.uiStyle()),
                Text('Status: ${worker.state}', style: context.uiStyle()),
              ],
            ),
          ),
      ],
    );
  }

  Widget _manifest(BuildContext context) {
    final colors = context.dt;
    final manifest = application.manifest;
    if (application.manifestUrl.isEmpty) {
      return DtEmptyState(application.loading ? 'Loading…' : 'No Web App Manifest detected.', detail: 'A page declares one with <link rel="manifest">.');
    }
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(text, style: context.uiStyle(color: colors.textStrong, size: 15, weight: FontWeight.w600)),
    );
    Widget row(String name, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 160, child: Text(name, style: context.uiStyle(color: colors.textDim))),
          Expanded(child: Text(value, style: context.uiStyle(color: colors.textStrong))),
        ],
      ),
    );
    const identity = ['name', 'short_name', 'description', 'id'];
    const presentation = ['start_url', 'scope', 'display', 'orientation', 'theme_color', 'background_color', 'lang', 'dir'];
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      children: [
        heading('App Manifest'),
        DtHover(
          cursor: SystemMouseCursors.click,
          onTap: () => widget.session.onOpenLink?.call(application.manifestUrl),
          builder: (context, hovered) => Text(application.manifestUrl, style: context.uiStyle(color: colors.accent)),
        ),
        if (application.manifestError.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(application.manifestError, style: context.uiStyle(color: colors.errorText))),
        if (manifest != null) ...[
          heading('Identity'),
          for (final key in identity)
            if (manifest[key] != null) row(key, '${manifest[key]}'),
          heading('Presentation'),
          for (final key in presentation)
            if (manifest[key] != null) row(key, '${manifest[key]}'),
          heading('Icons'),
          if (manifest.maps('icons').isEmpty) Text('No icons declared.', style: context.uiStyle(color: colors.textDim)),
          for (final icon in manifest.maps('icons')) row('${icon.str('sizes')} ${icon.str('type')}', icon.str('src')),
          for (final entry in manifest.entries)
            if (!identity.contains(entry.key) && !presentation.contains(entry.key) && entry.key != 'icons') row(entry.key, '${entry.value}'),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../util/css_color.dart';
import 'theme.dart';
import 'widgets.dart';

/// Shows a colour picker beside [anchor]. [onChanged] hears the colour as it
/// changes, and the future ends with whether the change was kept.
Future<bool> showColorPicker(
  BuildContext context, {
  required Offset anchor,
  required String initial,
  required ValueChanged<String> onChanged,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final color = parseCssColor(initial);
  if (overlay == null || color == null) return Future.value(false);
  final colors = context.dt;
  final done = Completer<bool>();
  late final OverlayEntry entry;
  void close(bool keep) {
    if (done.isCompleted) return;
    entry.remove();
    entry.dispose();
    done.complete(keep);
  }

  final box = overlay.context.findRenderObject()! as RenderBox;
  final at = box.globalToLocal(anchor);
  entry = OverlayEntry(
    builder: (context) => DtTheme(
      colors: colors,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(
              child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) => close(true)),
            ),
            Positioned(
              left: at.dx.clamp(4, constraints.maxWidth - 228),
              top: (at.dy + 10 + 220 > constraints.maxHeight ? at.dy - 230 : at.dy + 10).clamp(4, constraints.maxHeight),
              child: _ColorPicker(initial: initial, onChanged: onChanged, onClose: close),
            ),
          ],
        ),
      ),
    ),
  );
  overlay.insert(entry);
  return done.future;
}

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({required this.initial, required this.onChanged, required this.onClose});

  final String initial;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onClose;

  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late HSVColor _color = HSVColor.fromColor(parseCssColor(widget.initial)!);
  late final TextEditingController _text = TextEditingController(text: widget.initial);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(HSVColor next) {
    setState(() => _color = next);
    final text = formatCssColor(next.toColor(), like: widget.initial);
    _text.text = text;
    widget.onChanged(text);
  }

  Widget _drag({required Size size, required ValueChanged<Offset> onAt, required CustomPainter painter}) {
    void at(Offset local) => onAt(
      Offset((local.dx / size.width).clamp(0, 1), (local.dy / size.height).clamp(0, 1)),
    );
    return GestureDetector(
      onPanDown: (d) => at(d.localPosition),
      onPanUpdate: (d) => at(d.localPosition),
      child: CustomPaint(size: size, painter: painter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.dt;
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onChanged(widget.initial);
          widget.onClose(false);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onClose(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.popup,
          border: Border.all(color: colors.popupBorder),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _drag(
              size: const Size(198, 120),
              onAt: (p) => _set(_color.withSaturation(p.dx).withValue(1 - p.dy)),
              painter: _ShadePainter(_color),
            ),
            const SizedBox(height: 8),
            _drag(
              size: const Size(198, 12),
              onAt: (p) => _set(_color.withHue((p.dx * 360).clamp(0, 359.9))),
              painter: _SliderPainter(
                [for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, (h % 360).toDouble(), 1, 1).toColor()],
                _color.hue / 360,
              ),
            ),
            const SizedBox(height: 6),
            _drag(
              size: const Size(198, 12),
              onAt: (p) => _set(_color.withAlpha(p.dx)),
              painter: _SliderPainter(
                [_color.toColor().withValues(alpha: 0), _color.toColor().withValues(alpha: 1)],
                _color.alpha,
                checkered: true,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: colors.inputBackground,
                border: Border.all(color: colors.inputBorder),
              ),
              child: DtTextInput(
                controller: _text,
                style: context.monoStyle(color: colors.textStrong),
                onSubmitted: (value) {
                  final parsed = parseCssColor(value);
                  if (parsed == null) return;
                  setState(() => _color = HSVColor.fromColor(parsed));
                  widget.onChanged(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShadePainter extends CustomPainter {
  _ShadePainter(this.color);
  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, color.hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(colors: [const Color(0xFFFFFFFF), hue]).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
    final at = Offset(color.saturation * size.width, (1 - color.value) * size.height);
    canvas.drawCircle(at, 5, Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawCircle(at, 6.5, Paint()..color = const Color(0x80000000)..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_ShadePainter old) => old.color != color;
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.stops, this.value, {this.checkered = false});
  final List<Color> stops;
  final double value;
  final bool checkered;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)));
    if (checkered) paintCheckerboard(canvas, rect, 6);
    canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: stops).createShader(rect));
    canvas.restore();
    final x = value * size.width;
    final knob = RRect.fromLTRBR(x - 3, -1, x + 3, size.height + 1, const Radius.circular(2));
    canvas.drawRRect(knob, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(knob, Paint()..color = const Color(0x99000000)..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_SliderPainter old) => old.value != value || old.stops != stops;
}

void paintCheckerboard(Canvas canvas, Rect rect, double cell) {
  canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
  final dark = Paint()..color = const Color(0xFFCCCCCC);
  for (var y = 0; y * cell < rect.height; y++) {
    for (var x = y % 2; x * cell < rect.width; x += 2) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left + x * cell, rect.top + y * cell, cell, cell).intersect(rect),
        dark,
      );
    }
  }
}

/// The round sample of a colour beside a value.
class ColorSwatchDot extends StatelessWidget {
  const ColorSwatchDot(this.color, {super.key, this.onTapDown, this.size = 10});

  final Color color;
  final void Function(Offset position)? onTapDown;
  final double size;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: onTapDown == null ? MouseCursor.defer : SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onTapDown == null ? null : (d) => onTapDown!(d.globalPosition),
      onTap: onTapDown == null ? null : () {},
      child: Padding(
        padding: const EdgeInsets.only(right: 3),
        child: CustomPaint(size: Size.square(size), painter: _DotPainter(color, context.dt.splitterStrong)),
      ),
    ),
  );
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.color, this.border);
  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    if (color.a < 1) paintCheckerboard(canvas, rect, size.width / 3);
    canvas.drawRect(rect, Paint()..color = color);
    canvas.restore();
    canvas.drawOval(rect.deflate(0.5), Paint()..color = border..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.color != color || old.border != border;
}

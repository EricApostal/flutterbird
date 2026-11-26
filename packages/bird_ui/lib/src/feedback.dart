import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'pressable.dart';
import 'theme.dart';

/// How far along something is. Without a [value], that it is going.
class BirdProgressBar extends StatefulWidget {
  const BirdProgressBar({super.key, this.value, this.height = 4});

  final double? value;
  final double height;

  @override
  State<BirdProgressBar> createState() => _BirdProgressBarState();
}

class _BirdProgressBarState extends State<BirdProgressBar> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(BirdProgressBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  // Frames are only asked for while there is something to move.
  void _sync() {
    if (widget.value == null) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    return Semantics(
      value: widget.value == null ? null : '${(widget.value! * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.height / 2),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(painter: _BarPainter(widget.value, _sweep, colors.controlHover, colors.accent)),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.value, this.sweep, this.track, this.fill) : super(repaint: sweep);

  final double? value;
  final Animation<double> sweep;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final value = this.value;
    final width = value == null ? size.width * 0.3 : size.width * value.clamp(0.0, 1.0);
    final left = value == null ? (size.width + width) * sweep.value - width : 0.0;
    canvas.drawRect(Rect.fromLTWH(left, 0, width, size.height), Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.value != value || old.track != track || old.fill != fill;
}

/// Something is happening, and how long it will take is not known.
class BirdSpinner extends StatefulWidget {
  const BirdSpinner({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  State<BirdSpinner> createState() => _BirdSpinnerState();
}

class _BirdSpinnerState extends State<BirdSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: RotationTransition(
      turns: _turn,
      child: CustomPaint(painter: _SpinnerPainter(widget.color ?? context.bird.accent)),
    ),
  );
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(1.5, size.width / 9);
    final rect = (Offset.zero & size).deflate(stroke / 2 + 0.5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.22);
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 0.6, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.color != color;
}

/// A count or a word on the corner of [child].
class BirdBadge extends StatelessWidget {
  const BirdBadge({super.key, required this.child, required this.label, this.color, this.textColor});

  final Widget child;

  /// Nothing shows while this is empty.
  final String label;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return child;
    final colors = context.bird;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -5,
          right: -7,
          child: Container(
            constraints: const BoxConstraints(minWidth: 13),
            height: 13,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color ?? colors.accent, borderRadius: BorderRadius.circular(3)),
            child: Text(
              label,
              style: context.birdText(color: textColor ?? colors.onAccent, size: 9, weight: FontWeight.w700, height: 1.1),
            ),
          ),
        ),
      ],
    );
  }
}

enum BirdMessageKind { info, success, warning, error }

/// A strip that says how something went.
class BirdMessageBar extends StatelessWidget {
  const BirdMessageBar(this.message, {super.key, this.kind = BirdMessageKind.info, this.action});

  final String message;
  final BirdMessageKind kind;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    final (background, glyph, tint) = switch (kind) {
      BirdMessageKind.info => (colors.infoBackground, BirdGlyph.info, colors.accent),
      BirdMessageKind.success => (colors.successBackground, BirdGlyph.check, colors.success),
      BirdMessageKind.warning => (colors.warningBackground, BirdGlyph.warning, colors.warning),
      BirdMessageKind.error => (colors.dangerBackground, BirdGlyph.error, colors.danger),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(BirdRadius.control)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: BirdIcon(glyph, size: 14, color: tint)),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: context.birdText(size: BirdTextSize.small))),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
        ),
      ),
    );
  }
}

/// What a list says when it has nothing in it.
class BirdPlaceholder extends StatelessWidget {
  const BirdPlaceholder(this.message, {super.key, this.padding = const EdgeInsets.symmetric(vertical: 28, horizontal: 16)});

  final String message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: context.birdText(color: context.bird.textSecondary),
    ),
  );
}

/// A row of a list or a panel: an icon, one or two lines, and room at the end.
/// What is at the end has presses of its own.
class BirdListRow extends StatelessWidget {
  const BirdListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.leading,
    this.trailing,
    this.onPressed,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final bool enabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.bird;
    Widget body(BuildContext context) => Row(
      children: [
        if (leading != null) ...[
          SizedBox(width: 20, child: Center(child: leading)),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.birdText()),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.birdText(color: subtitleColor ?? colors.textSecondary, size: BirdTextSize.caption),
                ),
            ],
          ),
        ),
      ],
    );
    final height = subtitle == null ? 32.0 : 44.0;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: onPressed == null || !enabled
                  ? Container(height: height, padding: padding, child: body(context))
                  : BirdPressable(
                      onPressed: onPressed,
                      builder: (context, state) => BirdFocusRing(
                        visible: state.focused,
                        child: Container(
                          height: height,
                          padding: padding,
                          decoration: BoxDecoration(
                            color: state.pressed ? colors.pressed : (state.hovered ? colors.hover : null),
                            borderRadius: BorderRadius.circular(BirdRadius.control),
                          ),
                          child: body(context),
                        ),
                      ),
                    ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!, const SizedBox(width: 4)],
          ],
        ),
      ),
    );
  }
}

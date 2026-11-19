import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Ladybird's brand colors (UI/Qt/BrandColors.h in the engine's tree).
class _BrandColors {
  static const Color indigo30 = Color(0xFF6851D6);
  static const Color violet10 = Color(0xFFE0D4FF);
  static const Color violet20 = Color(0xFFCAB5FF);
  static const Color violet500 = Color(0xFF7A4CE6);
}

// A thin progress bar for a page that is loading.
//
// The engine only says whether a page is loading, not how far along it is, so
// the bar does not claim a percentage: while the page loads it eases towards
// most of the way across and never gets there by itself, and when the load
// finishes it runs the rest of the way and fades out. A highlight keeps sweeping
// across it so that a slow load still looks alive.
class TabLoadingBar extends StatefulWidget {
  const TabLoadingBar({super.key, required this.isLoading, this.height = 3});

  final ValueListenable<bool> isLoading;
  final double height;

  @override
  State<TabLoadingBar> createState() => _TabLoadingBarState();
}

class _TabLoadingBarState extends State<TabLoadingBar>
    with TickerProviderStateMixin {
  // How long the bar takes to creep to where it waits for the page, and how far
  // that is. It slows as it goes, so the first second moves it most.
  static const Duration _trickleDuration = Duration(seconds: 12);
  static const double _trickleTarget = 0.9;

  late final AnimationController _progress = AnimationController(vsync: this);
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.isLoading.addListener(_onLoadingChanged);
    if (widget.isLoading.value) _begin();
  }

  @override
  void didUpdateWidget(covariant TabLoadingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.isLoading, widget.isLoading)) return;
    oldWidget.isLoading.removeListener(_onLoadingChanged);
    widget.isLoading.addListener(_onLoadingChanged);
    _onLoadingChanged();
  }

  @override
  void dispose() {
    widget.isLoading.removeListener(_onLoadingChanged);
    _progress.dispose();
    _sweep.dispose();
    _opacity.dispose();
    super.dispose();
  }

  void _onLoadingChanged() {
    final loading = widget.isLoading.value;
    if (loading == _loading) return;
    if (loading) {
      _begin();
    } else {
      _finish();
    }
  }

  void _begin() {
    _loading = true;
    // Visible from the first frame, a little way in, rather than growing out of
    // nothing: the user has just done something and should see the bar answer.
    _progress.value = 0.04;
    _opacity.value = 1;
    _progress.animateTo(
      _trickleTarget,
      duration: _trickleDuration,
      curve: Curves.easeOutCubic,
    );
    if (!_sweep.isAnimating) _sweep.repeat();
  }

  void _finish() {
    _loading = false;
    _progress
        .animateTo(
          1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
        .whenCompleteOrCancel(() {
          // Another load may have started while this one finished.
          if (!mounted || _loading) return;
          _opacity.reverse().whenCompleteOrCancel(() {
            if (!mounted || _loading) return;
            _sweep.stop();
            _progress.value = 0;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TabLoadingBarPainter(progress: _progress, sweep: _sweep),
          ),
        ),
      ),
    );
  }
}

class _TabLoadingBarPainter extends CustomPainter {
  _TabLoadingBarPainter({required this.progress, required this.sweep})
    : super(repaint: Listenable.merge([progress, sweep]));

  final Animation<double> progress;
  final Animation<double> sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final filled = size.width * progress.value.clamp(0.0, 1.0);
    if (filled <= 0) return;

    final height = size.height;
    final bar = RRect.fromLTRBAndCorners(
      0,
      0,
      filled,
      height,
      topRight: Radius.circular(height / 2),
      bottomRight: Radius.circular(height / 2),
    );

    // A soft glow, which spills a little onto the page below the bar.
    canvas.drawRRect(
      bar,
      Paint()
        ..color = _BrandColors.violet500.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawRRect(
      bar,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            _BrandColors.indigo30,
            _BrandColors.violet500,
            _BrandColors.violet20,
          ],
          stops: [0, 0.7, 1],
        ).createShader(Rect.fromLTWH(0, 0, filled, height)),
    );

    // A highlight that runs across the filled part, again and again.
    const bandWidth = 96.0;
    final bandLeft = -bandWidth + (filled + bandWidth) * sweep.value;
    final band = Rect.fromLTWH(bandLeft, 0, bandWidth, height);
    canvas.save();
    canvas.clipRRect(bar);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    canvas.restore();

    // A bright head at the leading edge.
    final headCenter = Offset(filled - height / 2, height / 2);
    final headRadius = height * 1.8;
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _BrandColors.violet10.withValues(alpha: 0.95),
            _BrandColors.violet20.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: headCenter, radius: headRadius)),
    );
  }

  @override
  bool shouldRepaint(covariant _TabLoadingBarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.sweep != sweep;
}

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

/// The thin line along the toolbar's edge while a page loads.
///
/// The engine only says whether a page is loading, not how far along it is, so
/// the line eases towards most of the way across, runs the rest of the way when
/// the load finishes, and fades out.
class MobileProgressBar extends StatefulWidget {
  const MobileProgressBar({required this.isLoading, super.key});

  static const double height = 2.5;

  final ValueListenable<bool> isLoading;

  @override
  State<MobileProgressBar> createState() => _MobileProgressBarState();
}

class _MobileProgressBarState extends State<MobileProgressBar>
    with TickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(vsync: this);
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.isLoading.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(MobileProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.isLoading, widget.isLoading)) return;
    oldWidget.isLoading.removeListener(_changed);
    widget.isLoading.addListener(_changed);
    // Another tab's line starts from nothing.
    _loading = false;
    _progress.value = 0;
    _opacity.value = 0;
    _changed();
  }

  @override
  void dispose() {
    widget.isLoading.removeListener(_changed);
    _progress.dispose();
    _opacity.dispose();
    super.dispose();
  }

  void _changed() {
    final loading = widget.isLoading.value;
    if (loading == _loading) return;
    _loading = loading;
    if (loading) {
      _progress.value = 0.08;
      _opacity.value = 1;
      _progress.animateTo(
        0.9,
        duration: const Duration(seconds: 12),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _progress
        .animateTo(
          1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (mounted && !_loading) _opacity.reverse();
        });
  }

  @override
  Widget build(BuildContext context) {
    final color = context.mobile.accent;
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: SizedBox(
          height: MobileProgressBar.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _progress,
            builder: (context, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _progress.value.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

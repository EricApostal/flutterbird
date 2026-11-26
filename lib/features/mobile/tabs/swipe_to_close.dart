import 'package:material_ui/material_ui.dart';

/// A card that can be swiped off to either side.
class SwipeToClose extends StatefulWidget {
  const SwipeToClose({
    required this.enabled,
    required this.onClosed,
    required this.child,
    super.key,
  });

  final bool enabled;

  /// Called once the card has left the screen.
  final VoidCallback onClosed;
  final Widget child;

  @override
  State<SwipeToClose> createState() => _SwipeToCloseState();
}

class _SwipeToCloseState extends State<SwipeToClose>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _end(DragEndDetails details) {
    final width = context.size?.width ?? 1;
    final velocity = details.primaryVelocity ?? 0;
    final offset = _offset.value;
    final flung = velocity.abs() > 700 && velocity.sign == offset.sign;

    if (offset.abs() < width * 0.45 && !flung) {
      _offset.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
      );
      return;
    }
    _offset
        .animateTo(
          offset.sign * MediaQuery.sizeOf(context).width,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (mounted) widget.onClosed();
        });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: widget.enabled ? (_) => _offset.stop() : null,
      onHorizontalDragUpdate: widget.enabled
          ? (details) => _offset.value += details.primaryDelta ?? 0
          : null,
      onHorizontalDragEnd: widget.enabled ? _end : null,
      onHorizontalDragCancel: widget.enabled ? () => _offset.value = 0 : null,
      child: AnimatedBuilder(
        animation: _offset,
        child: widget.child,
        builder: (context, child) {
          final width = MediaQuery.sizeOf(context).width;
          final progress = (_offset.value / width).clamp(-1.0, 1.0);
          return Transform.translate(
            offset: Offset(_offset.value, 0),
            child: Transform.rotate(
              angle: progress * 0.12,
              child: Opacity(
                opacity: (1 - progress.abs() * 1.3).clamp(0.0, 1.0),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}

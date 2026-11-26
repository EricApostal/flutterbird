import 'dart:async';

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A hint shown after the pointer rests.
class BirdTooltip extends StatefulWidget {
  const BirdTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<BirdTooltip> createState() => _BirdTooltipState();
}

class _BirdTooltipState extends State<BirdTooltip> {
  final OverlayPortalController _portal = OverlayPortalController();
  Timer? _timer;
  Offset _pointer = Offset.zero;

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _portal.show();
    });
  }

  void _hide() {
    _timer?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty || Overlay.maybeOf(context) == null) {
      return widget.child;
    }
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        final colors = context.bird;
        final box = Overlay.of(context).context.findRenderObject();
        final at = box is RenderBox ? box.globalToLocal(_pointer) : _pointer;
        return Positioned.fill(
          child: IgnorePointer(
            child: CustomSingleChildLayout(
              delegate: _NearPointer(at),
              child: BirdTheme(
                colors: colors,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.panel,
                    border: Border.all(color: colors.panelBorder),
                    borderRadius: BorderRadius.circular(BirdRadius.control),
                    boxShadow: [
                      BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
                    ],
                  ),
                  child: Text(
                    widget.message,
                    style: context.birdText(color: colors.text, size: BirdTextSize.caption),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (event) {
          _pointer = event.position;
          _schedule();
        },
        onHover: (event) => _pointer = event.position,
        onExit: (_) => _hide(),
        child: Listener(onPointerDown: (_) => _hide(), child: widget.child),
      ),
    );
  }
}

class _NearPointer extends SingleChildLayoutDelegate {
  _NearPointer(this.at);
  final Offset at;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = at.dx + 8;
    var y = at.dy + 18;
    if (x + child.width > size.width - 4) x = size.width - child.width - 4;
    if (y + child.height > size.height - 4) y = at.dy - child.height - 8;
    return Offset(x.clamp(0, size.width), y.clamp(0, size.height));
  }

  @override
  bool shouldRelayout(_NearPointer old) => old.at != at;
}


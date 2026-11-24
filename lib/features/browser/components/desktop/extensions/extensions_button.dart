import 'package:flutter/material.dart';
import 'package:flutterbird/features/extensions/extensions_panel.dart';

// Toolbar entry point for extensions: an icon button that toggles an anchored
// popover, built the same way as the downloads one.
class ExtensionsButton extends StatefulWidget {
  const ExtensionsButton({super.key});

  @override
  State<ExtensionsButton> createState() => _ExtensionsButtonState();
}

class _ExtensionsButtonState extends State<ExtensionsButton> {
  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (context) {
          return Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _overlayController.hide,
              child: CompositedTransformFollower(
                link: _layerLink,
                targetAnchor: Alignment.bottomRight,
                followerAnchor: Alignment.topRight,
                offset: const Offset(0, 8),
                child: Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {}, // swallow so it doesn't bubble to the barrier
                    child: ExtensionsPanel(onClose: _overlayController.hide),
                  ),
                ),
              ),
            ),
          );
        },
        child: IconButton(
          tooltip: 'Extensions',
          icon: const Icon(Icons.extension_outlined, size: 20),
          onPressed: _overlayController.toggle,
        ),
      ),
    );
  }
}

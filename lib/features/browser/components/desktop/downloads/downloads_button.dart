import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/downloads/downloads_panel.dart';
import 'package:ladybird/ladybird.dart';

// Toolbar entry point for downloads: a badge-count icon button that toggles
// an anchored popover (kept alive via OverlayPortal so it can rebuild live as
// download progress changes, unlike the showMenu-based toolbar menu).
class DownloadsButton extends StatefulWidget {
  const DownloadsButton({super.key});

  @override
  State<DownloadsButton> createState() => _DownloadsButtonState();
}

class _DownloadsButtonState extends State<DownloadsButton> {
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
                    child: ValueListenableBuilder<List<LadybirdDownload>>(
                      valueListenable: LadybirdController.downloadsNotifier,
                      builder: (context, downloads, _) {
                        return DownloadsPanel(
                          downloads: downloads,
                          onClose: _overlayController.hide,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: ValueListenableBuilder<List<LadybirdDownload>>(
          valueListenable: LadybirdController.downloadsNotifier,
          builder: (context, downloads, _) {
            final activeCount = downloads
                .where((download) => download.isInProgress)
                .length;
            return IconButton(
              tooltip: 'Downloads',
              icon: Badge(
                isLabelVisible: activeCount > 0,
                label: Text('$activeCount'),
                child: const Icon(Icons.download_outlined, size: 20),
              ),
              onPressed: _overlayController.toggle,
            );
          },
        ),
      ),
    );
  }
}

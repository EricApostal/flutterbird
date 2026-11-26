import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:rubisco_browser/features/browser/components/desktop/downloads/downloads_panel.dart';
import 'package:ladybird/ladybird.dart';

// Toolbar entry point for downloads: a button with a count of those going,
// which opens a panel that follows their progress.
class DownloadsButton extends StatefulWidget {
  const DownloadsButton({super.key});

  @override
  State<DownloadsButton> createState() => _DownloadsButtonState();
}

class _DownloadsButtonState extends State<DownloadsButton> {
  final OverlayPortalController _overlayController = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    return BirdPopover(
      controller: _overlayController,
      align: BirdPopoverAlign.end,
      onDismiss: () => setState(() {}),
      popoverBuilder: (context) {
        return ValueListenableBuilder<List<LadybirdDownload>>(
          valueListenable: LadybirdController.downloadsNotifier,
          builder: (context, downloads, _) {
            return DownloadsPanel(
              downloads: downloads,
              onClose: () => setState(_overlayController.hide),
            );
          },
        );
      },
      child: ValueListenableBuilder<List<LadybirdDownload>>(
        valueListenable: LadybirdController.downloadsNotifier,
        builder: (context, downloads, _) {
          final activeCount = downloads
              .where((download) => download.isInProgress)
              .length;
          return BirdBadge(
            label: activeCount > 0 ? '$activeCount' : '',
            child: BirdToolbarButton(
              glyph: BirdGlyph.download,
              tooltip: 'Downloads',
              active: _overlayController.isShowing,
              onPressed: () => setState(_overlayController.toggle),
            ),
          );
        },
      ),
    );
  }
}

import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:rubisco_browser/features/browser/components/desktop/downloads/download_row.dart';
import 'package:ladybird/ladybird.dart';

class DownloadsPanel extends StatelessWidget {
  final List<LadybirdDownload> downloads;
  final VoidCallback onClose;

  const DownloadsPanel({
    required this.downloads,
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BirdPanel(
      width: 360,
      constraints: const BoxConstraints(maxHeight: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BirdPanelHeader('Downloads', onClose: onClose),
          Flexible(
            child: downloads.isEmpty
                ? const BirdPlaceholder('No downloads yet')
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: downloads.length,
                    separatorBuilder: (context, index) =>
                        const BirdSeparator(),
                    itemBuilder: (context, index) {
                      final download = downloads[index];
                      return DownloadRow(
                        download: download,
                        onCancel: () =>
                            LadybirdController.cancelDownload(download.id),
                        onOpen: () =>
                            LadybirdController.openDownload(download.id),
                        onShowInFolder: () =>
                            LadybirdController.showDownloadInFolder(
                              download.id,
                            ),
                        onDismiss: () => _dismiss(download.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // There's no native "remove a single download" call, only a bulk prune of
  // everything inactive — fine here since dismiss is only offered for
  // already-inactive (failed/canceled) rows.
  void _dismiss(int id) {
    LadybirdController.pruneInactiveDownloads();
  }
}

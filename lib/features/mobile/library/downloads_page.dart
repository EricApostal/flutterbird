import 'package:bird_session/bird_session.dart';
import 'package:ladybird/ladybird.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rubisco_browser/features/mobile/library/library_widgets.dart';
import 'package:rubisco_browser/features/mobile/mobile_actions.dart';
import 'package:rubisco_browser/features/mobile/theme/mobile_theme.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  static String _detail(LadybirdDownload download) {
    final done = formatBytes(download.downloadedSize);
    final total = download.totalSize;
    final of = total == null || total <= 0
        ? done
        : '$done of ${formatBytes(total)}';
    return switch (download.status) {
      LadybirdDownloadStatus.inProgress => of,
      LadybirdDownloadStatus.paused => 'Paused · $of',
      LadybirdDownloadStatus.completed => [
        done,
        siteHost(download.url),
      ].where((part) => part.isNotEmpty).join(' · '),
      LadybirdDownloadStatus.canceled => 'Canceled',
      LadybirdDownloadStatus.failed => download.error ?? 'Download failed',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mobile;
    return ValueListenableBuilder<List<LadybirdDownload>>(
      valueListenable: LadybirdController.downloadsNotifier,
      builder: (context, downloads, _) {
        final hasFinished = downloads.any(
          (download) => !download.isInProgress && !download.isPaused,
        );
        return LibraryScreen(
          title: 'Downloads',
          actions: [
            if (hasFinished)
              TextButton(
                onPressed: LadybirdController.pruneInactiveDownloads,
                child: const Text('Clear list'),
              ),
          ],
          child: downloads.isEmpty
              ? const LibraryEmpty(
                  icon: Icons.download_done_rounded,
                  message: 'Files you download appear here',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: downloads.length,
                  itemBuilder: (context, index) {
                    final download = downloads[index];
                    final active = download.isInProgress || download.isPaused;
                    return LibraryRow(
                      key: ValueKey(download.id),
                      leading: Icon(
                        switch (download.status) {
                          LadybirdDownloadStatus.completed =>
                            Icons.insert_drive_file_outlined,
                          LadybirdDownloadStatus.failed => Icons.error_outline,
                          LadybirdDownloadStatus.canceled => Icons.block,
                          LadybirdDownloadStatus.inProgress ||
                          LadybirdDownloadStatus.paused =>
                            Icons.arrow_downward_rounded,
                        },
                        size: 20,
                        color: download.isFailed
                            ? colors.danger
                            : colors.textSecondary,
                      ),
                      title: download.fileName,
                      subtitle: _detail(download),
                      below: active
                          ? LinearProgressIndicator(
                              value: download.progress,
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                            )
                          : null,
                      onTap: download.isCompleted
                          ? () => LadybirdController.openDownload(download.id)
                          : null,
                      trailing: active
                          ? IconButton(
                              tooltip: 'Cancel download',
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () =>
                                  LadybirdController.cancelDownload(
                                    download.id,
                                  ),
                            )
                          : IconButton(
                              tooltip: 'Copy download address',
                              icon: Icon(
                                Icons.link_rounded,
                                size: 20,
                                color: colors.textSecondary,
                              ),
                              onPressed: () => copyText(context, download.url),
                            ),
                    );
                  },
                ),
        );
      },
    );
  }
}

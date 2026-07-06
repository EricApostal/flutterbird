import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/desktop/downloads/download_row.dart';
import 'package:flutterbird/features/browser/components/desktop/omnibox/omnibox_style.dart';
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
    final theme = Theme.of(context);

    return Material(
      elevation: 6,
      color: omniboxSurfaceColor(theme),
      borderRadius: BorderRadius.circular(kOmniboxFieldRadius),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Downloads', style: theme.textTheme.titleSmall),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Close',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: theme.colorScheme.outline.withAlpha(50),
            ),
            Flexible(
              child: downloads.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        'No downloads yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: downloads.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: theme.colorScheme.outline.withAlpha(50),
                      ),
                      itemBuilder: (context, index) {
                        final download = downloads[index];
                        return DownloadRow(
                          download: download,
                          onCancel: () =>
                              LadybirdController.cancelDownload(download.id),
                          onOpen: () =>
                              LadybirdController.openDownload(download.id),
                          onShowInFolder: () => LadybirdController
                              .showDownloadInFolder(download.id),
                          onDismiss: () => _dismiss(download.id),
                        );
                      },
                    ),
            ),
          ],
        ),
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

import 'package:flutter/material.dart';
import 'package:ladybird/ladybird.dart';

class DownloadRow extends StatelessWidget {
  final LadybirdDownload download;
  final VoidCallback onCancel;
  final VoidCallback onOpen;
  final VoidCallback onShowInFolder;
  final VoidCallback onDismiss;

  const DownloadRow({
    required this.download,
    required this.onCancel,
    required this.onOpen,
    required this.onShowInFolder,
    required this.onDismiss,
    super.key,
  });

  String _statusLabel() {
    final sizeLabel = _formatSize(download.downloadedSize, download.totalSize);
    switch (download.status) {
      case LadybirdDownloadStatus.inProgress:
        return sizeLabel;
      case LadybirdDownloadStatus.paused:
        return 'Paused · $sizeLabel';
      case LadybirdDownloadStatus.completed:
        return 'Completed · $sizeLabel';
      case LadybirdDownloadStatus.canceled:
        return 'Canceled';
      case LadybirdDownloadStatus.failed:
        return download.error?.isNotEmpty == true
            ? 'Failed · ${download.error}'
            : 'Failed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleColor = download.isFailed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconForStatus(download.status),
                size: 18,
                color: subtitleColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      download.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      _statusLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _TrailingAction(
                download: download,
                onCancel: onCancel,
                onOpen: onOpen,
                onShowInFolder: onShowInFolder,
                onDismiss: onDismiss,
              ),
            ],
          ),
          if (download.isInProgress || download.isPaused) ...[
            const SizedBox(height: 6),
            _AnimatedDownloadProgressBar(progress: download.progress),
          ],
        ],
      ),
    );
  }

  IconData _iconForStatus(LadybirdDownloadStatus status) {
    switch (status) {
      case LadybirdDownloadStatus.inProgress:
        return Icons.file_download_outlined;
      case LadybirdDownloadStatus.paused:
        return Icons.pause_circle_outline;
      case LadybirdDownloadStatus.completed:
        return Icons.check_circle_outline;
      case LadybirdDownloadStatus.canceled:
        return Icons.cancel_outlined;
      case LadybirdDownloadStatus.failed:
        return Icons.error_outline;
    }
  }
}

class _TrailingAction extends StatelessWidget {
  final LadybirdDownload download;
  final VoidCallback onCancel;
  final VoidCallback onOpen;
  final VoidCallback onShowInFolder;
  final VoidCallback onDismiss;

  const _TrailingAction({
    required this.download,
    required this.onCancel,
    required this.onOpen,
    required this.onShowInFolder,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (download.isInProgress) {
      return IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Cancel',
        onPressed: onCancel,
      );
    }
    if (download.isCompleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.folder_open, size: 18),
            tooltip: 'Show in folder',
            onPressed: onShowInFolder,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 18),
            tooltip: 'Open',
            onPressed: onOpen,
          ),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.close, size: 18),
      tooltip: 'Dismiss',
      onPressed: onDismiss,
    );
  }
}

// A progress bar that smoothly eases toward each new [progress] value rather
// than jumping, so rapid download-chunk updates read as continuous motion.
// `null` means the total size is unknown, so it falls back to an
// indeterminate (already-animating) indicator.
class _AnimatedDownloadProgressBar extends StatelessWidget {
  final double? progress;

  const _AnimatedDownloadProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final target = progress;
    final bar = target == null
        ? const LinearProgressIndicator(minHeight: 4)
        : TweenAnimationBuilder<double>(
            tween: Tween<double>(end: target),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return LinearProgressIndicator(value: value, minHeight: 4);
            },
          );

    return ClipRRect(borderRadius: BorderRadius.circular(4), child: bar);
  }
}

String _formatSize(int downloaded, int? total) {
  final downloadedLabel = _formatBytes(downloaded);
  if (total == null) return downloadedLabel;
  return '$downloadedLabel of ${_formatBytes(total)}';
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  double size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final precision = unitIndex == 0 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
}

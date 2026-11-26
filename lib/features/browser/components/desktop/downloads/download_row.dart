import 'package:bird_ui/bird_ui.dart';
import 'package:flutter/widgets.dart';
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
    final colors = context.bird;
    final subtitleColor = download.isFailed
        ? colors.danger
        : colors.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BirdIcon(
                _glyphForStatus(download.status),
                size: 16,
                color: subtitleColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      download.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.birdText(),
                    ),
                    Text(
                      _statusLabel(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.birdText(
                        color: subtitleColor,
                        size: BirdTextSize.caption,
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

  BirdGlyph _glyphForStatus(LadybirdDownloadStatus status) {
    switch (status) {
      case LadybirdDownloadStatus.inProgress:
        return BirdGlyph.download;
      case LadybirdDownloadStatus.paused:
        return BirdGlyph.pause;
      case LadybirdDownloadStatus.completed:
        return BirdGlyph.check;
      case LadybirdDownloadStatus.canceled:
        return BirdGlyph.close;
      case LadybirdDownloadStatus.failed:
        return BirdGlyph.error;
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

  Widget _button(BirdGlyph glyph, String tooltip, VoidCallback onPressed) =>
      BirdToolbarButton(
        glyph: glyph,
        tooltip: tooltip,
        size: 28,
        iconSize: 14,
        onPressed: onPressed,
      );

  @override
  Widget build(BuildContext context) {
    if (download.isInProgress) {
      return _button(BirdGlyph.close, 'Cancel', onCancel);
    }
    if (download.isCompleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(BirdGlyph.folder, 'Show in folder', onShowInFolder),
          _button(BirdGlyph.openExternal, 'Open', onOpen),
        ],
      );
    }
    return _button(BirdGlyph.close, 'Dismiss', onDismiss);
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
    return target == null
        ? const BirdProgressBar()
        : TweenAnimationBuilder<double>(
            tween: Tween<double>(end: target),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return BirdProgressBar(value: value);
            },
          );
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

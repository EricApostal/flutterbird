import 'package:dart_mappable/dart_mappable.dart';

part 'download.mapper.dart';

@MappableEnum()
enum LadybirdDownloadStatus {
  @MappableValue('in-progress')
  inProgress,
  completed,
  canceled,
  failed,
}

@MappableClass()
class LadybirdDownload with LadybirdDownloadMappable {
  const LadybirdDownload({
    required this.id,
    required this.url,
    required this.fileName,
    required this.destination,
    required this.status,
    required this.downloadedSize,
    this.totalSize,
    this.error,
  });

  final int id;
  final String url;
  final String fileName;
  final String destination;
  final LadybirdDownloadStatus status;
  final int downloadedSize;
  final int? totalSize;
  final String? error;

  bool get isInProgress => status == LadybirdDownloadStatus.inProgress;
  bool get isCompleted => status == LadybirdDownloadStatus.completed;
  bool get isFailed => status == LadybirdDownloadStatus.failed;
  bool get isCanceled => status == LadybirdDownloadStatus.canceled;

  // Fraction in [0, 1], or null when the total size is unknown (indeterminate
  // progress).
  double? get progress {
    final total = totalSize;
    if (total == null || total <= 0) return null;
    return (downloadedSize / total).clamp(0.0, 1.0);
  }
}

import 'dart:io';
import 'dart:typed_data';

import 'zip_reader.dart';

/// The way an XPI's contents may be written to disk.
class ExtractionLimits {
  const ExtractionLimits({
    this.maxEntryBytes = ZipArchive.defaultMaxEntryBytes,
    this.maxTotalBytes = 512 * 1024 * 1024,
  });

  final int maxEntryBytes;
  final int maxTotalBytes;
}

/// Returns [name] as a normalized relative path using `/` separators, or
/// null when it could escape the directory it is extracted into.
///
/// Archive entry names are attacker-controlled. A name that is absolute,
/// names a drive, contains a backslash (a separator on Windows) or climbs
/// with `..` is rejected rather than repaired.
String? safeRelativePath(String name) {
  if (name.isEmpty || name.contains('\u0000') || name.contains('\\')) {
    return null;
  }
  if (name.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(name)) {
    return null;
  }

  final segments = <String>[];
  for (final segment in name.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') return null;
    segments.add(segment);
  }
  if (segments.isEmpty) return null;
  return segments.join('/');
}

/// Writes every file of [archive] under [destination], which must exist.
///
/// `META-INF/` holds Mozilla's signature files and is not needed once the
/// package has been accepted, so it is skipped. Returns the relative paths
/// that were written.
Future<List<String>> extractArchive(
  ZipArchive archive,
  Directory destination, {
  ExtractionLimits limits = const ExtractionLimits(),
}) async {
  final root = destination.absolute.path;
  final written = <String>[];
  final claimed = <String>{};
  var total = 0;

  for (final entry in archive.entries) {
    final relative = safeRelativePath(entry.name);
    if (relative == null) {
      throw ZipFormatException('Unsafe entry name "${entry.name}"');
    }
    if (relative == 'META-INF' || relative.startsWith('META-INF/')) continue;

    // Case-insensitive filesystems would let "a.js" and "A.js" overwrite each
    // other, so two names that differ only by case cannot both be extracted.
    if (!claimed.add(relative.toLowerCase())) {
      throw ZipFormatException('Entry "$relative" collides with another entry');
    }

    final target =
        '$root${Platform.pathSeparator}'
        '${relative.replaceAll('/', Platform.pathSeparator)}';

    if (entry.isDirectory) {
      await Directory(target).create(recursive: true);
      continue;
    }

    total += entry.uncompressedSize;
    if (total > limits.maxTotalBytes) {
      throw ZipFormatException('Archive inflates past the total size limit');
    }

    final Uint8List contents = archive.read(
      entry,
      maxBytes: limits.maxEntryBytes,
    );
    final file = File(target);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(contents, flush: false);
    written.add(relative);
  }

  return written;
}

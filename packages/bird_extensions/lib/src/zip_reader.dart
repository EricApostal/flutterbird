import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

/// Thrown when an archive is malformed, uses an unsupported feature, or
/// breaks one of the safety limits below.
class ZipFormatException implements Exception {
  ZipFormatException(this.message);

  final String message;

  @override
  String toString() => 'ZipFormatException: $message';
}

/// One member of a ZIP archive, as listed by its central directory.
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.crc32,
    required this.localHeaderOffset,
  });

  final String name;

  /// 0 for stored, 8 for deflated. Nothing else is supported.
  final int method;
  final int compressedSize;
  final int uncompressedSize;
  final int crc32;
  final int localHeaderOffset;

  bool get isDirectory => name.endsWith('/');
}

/// A read-only ZIP reader, which is all an XPI needs.
///
/// Archives come from the network, so the reader is deliberately strict
/// rather than forgiving: duplicate names, encryption, ZIP64 and sizes that
/// do not match what actually decompresses are all errors, and every read is
/// bounded by [maxEntryBytes] before anything is inflated.
class ZipArchive {
  ZipArchive._(this._bytes, this.entries) {
    for (final entry in entries) {
      _byName[entry.name] = entry;
    }
  }

  /// The most one entry may inflate to. XPIs are small; the largest ones on
  /// AMO ship a few hundred megabytes of dictionaries or language data.
  static const int defaultMaxEntryBytes = 256 * 1024 * 1024;

  static const int _eocdSignature = 0x06054b50;
  static const int _centralSignature = 0x02014b50;
  static const int _localSignature = 0x04034b50;
  static const int _eocdMinSize = 22;
  static const int _maxCommentSize = 0xFFFF;

  final Uint8List _bytes;
  final List<ZipEntry> entries;
  final Map<String, ZipEntry> _byName = {};

  factory ZipArchive.fromBytes(Uint8List bytes, {int maxEntries = 50000}) {
    final data = ByteData.sublistView(bytes);
    final eocd = _findEndOfCentralDirectory(bytes, data);

    final entryCount = data.getUint16(eocd + 10, Endian.little);
    final centralSize = data.getUint32(eocd + 12, Endian.little);
    final centralOffset = data.getUint32(eocd + 16, Endian.little);

    if (entryCount == 0xFFFF ||
        centralSize == 0xFFFFFFFF ||
        centralOffset == 0xFFFFFFFF) {
      throw ZipFormatException('ZIP64 archives are not supported');
    }
    if (entryCount > maxEntries) {
      throw ZipFormatException('Archive has too many entries ($entryCount)');
    }
    if (centralOffset + centralSize > eocd) {
      throw ZipFormatException('Central directory is out of bounds');
    }

    final entries = <ZipEntry>[];
    final seen = <String>{};
    var position = centralOffset;

    for (var index = 0; index < entryCount; index++) {
      if (position + 46 > bytes.length ||
          data.getUint32(position, Endian.little) != _centralSignature) {
        throw ZipFormatException('Bad central directory entry #$index');
      }

      final flags = data.getUint16(position + 8, Endian.little);
      final method = data.getUint16(position + 10, Endian.little);
      final crc = data.getUint32(position + 16, Endian.little);
      final compressedSize = data.getUint32(position + 20, Endian.little);
      final uncompressedSize = data.getUint32(position + 24, Endian.little);
      final nameLength = data.getUint16(position + 28, Endian.little);
      final extraLength = data.getUint16(position + 30, Endian.little);
      final commentLength = data.getUint16(position + 32, Endian.little);
      final localOffset = data.getUint32(position + 42, Endian.little);

      final next = position + 46 + nameLength + extraLength + commentLength;
      if (next > eocd) {
        throw ZipFormatException('Central directory entry #$index overruns');
      }
      if (flags & 0x1 != 0) {
        throw ZipFormatException('Encrypted entries are not supported');
      }
      if (compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF) {
        throw ZipFormatException('ZIP64 entries are not supported');
      }

      final nameBytes = Uint8List.sublistView(
        bytes,
        position + 46,
        position + 46 + nameLength,
      );
      final name = _decodeName(nameBytes, utf8Flag: flags & 0x800 != 0);

      // Two entries with one name make "which one wins" depend on the reader,
      // which is how archive-confusion attacks work. Refuse them outright.
      if (!seen.add(name)) {
        throw ZipFormatException('Duplicate entry "$name"');
      }

      entries.add(
        ZipEntry(
          name: name,
          method: method,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          crc32: crc,
          localHeaderOffset: localOffset,
        ),
      );
      position = next;
    }

    return ZipArchive._(bytes, entries);
  }

  ZipEntry? find(String name) => _byName[name];

  /// Returns the inflated, CRC-checked contents of [entry].
  Uint8List read(ZipEntry entry, {int maxBytes = defaultMaxEntryBytes}) {
    if (entry.isDirectory) return Uint8List(0);
    if (entry.uncompressedSize > maxBytes) {
      throw ZipFormatException(
        '"${entry.name}" is larger than the $maxBytes-byte limit',
      );
    }

    final data = ByteData.sublistView(_bytes);
    final offset = entry.localHeaderOffset;
    if (offset + 30 > _bytes.length ||
        data.getUint32(offset, Endian.little) != _localSignature) {
      throw ZipFormatException('Bad local header for "${entry.name}"');
    }

    final nameLength = data.getUint16(offset + 26, Endian.little);
    final extraLength = data.getUint16(offset + 28, Endian.little);
    final start = offset + 30 + nameLength + extraLength;
    final end = start + entry.compressedSize;
    if (end > _bytes.length) {
      throw ZipFormatException('"${entry.name}" runs past the end of the file');
    }

    final stored = Uint8List.sublistView(_bytes, start, end);
    final Uint8List contents;

    switch (entry.method) {
      case 0:
        if (entry.compressedSize != entry.uncompressedSize) {
          throw ZipFormatException(
            'Stored entry "${entry.name}" size mismatch',
          );
        }
        contents = stored;
      case 8:
        contents = _inflate(stored, entry);
      default:
        throw ZipFormatException(
          'Unsupported compression method ${entry.method} for "${entry.name}"',
        );
    }

    if (contents.length != entry.uncompressedSize) {
      throw ZipFormatException('"${entry.name}" has the wrong inflated size');
    }
    if (crc32(contents) != entry.crc32) {
      throw ZipFormatException('"${entry.name}" failed its CRC check');
    }
    return contents;
  }

  static Uint8List _inflate(Uint8List compressed, ZipEntry entry) {
    // Inflate in chunks into a collector that stops at the declared size, so
    // a hostile stream cannot allocate more than the entry claims to be.
    final collector = _BoundedCollector(entry.uncompressedSize, entry.name);
    final decoder = ZLibDecoder(raw: true).startChunkedConversion(collector);
    try {
      decoder.add(compressed);
      decoder.close();
    } on ZipFormatException {
      rethrow;
    } on Object catch (error) {
      throw ZipFormatException('Could not inflate "${entry.name}": $error');
    }
    return collector.takeBytes();
  }

  static int _findEndOfCentralDirectory(Uint8List bytes, ByteData data) {
    if (bytes.length < _eocdMinSize) {
      throw ZipFormatException('File is too small to be a ZIP archive');
    }

    final lowest = (bytes.length - _eocdMinSize - _maxCommentSize).clamp(
      0,
      bytes.length,
    );
    for (var i = bytes.length - _eocdMinSize; i >= lowest; i--) {
      if (data.getUint32(i, Endian.little) != _eocdSignature) continue;
      final commentLength = data.getUint16(i + 20, Endian.little);
      if (i + _eocdMinSize + commentLength == bytes.length) return i;
    }
    throw ZipFormatException('Not a ZIP archive (no end of central directory)');
  }

  static String _decodeName(Uint8List bytes, {required bool utf8Flag}) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      if (utf8Flag) {
        throw ZipFormatException('Entry name is not valid UTF-8');
      }
      return latin1.decode(bytes);
    }
  }
}

class _BoundedCollector implements Sink<List<int>> {
  _BoundedCollector(this._limit, this._name);

  final int _limit;
  final String _name;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (_builder.length + data.length > _limit) {
      throw ZipFormatException('"$_name" inflates past its declared size');
    }
    _builder.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    table[n] = c;
  }
  return table;
}();

/// The CRC-32 that ZIP uses.
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

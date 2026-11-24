import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bird_extensions/bird_extensions.dart';

/// One file to put in a test archive.
class ZipItem {
  ZipItem(
    this.name,
    this.data, {
    this.deflate = true,
    this.crcOverride,
    this.declaredSizeOverride,
  });

  ZipItem.text(String name, String text, {bool deflate = true})
    : this(name, utf8.encode(text), deflate: deflate);

  final String name;
  final List<int> data;
  final bool deflate;

  /// Writes this CRC instead of the real one.
  final int? crcOverride;

  /// Writes this uncompressed size instead of the real one.
  final int? declaredSizeOverride;
}

/// Builds a ZIP archive in memory. It writes exactly what [items] says, even
/// when that is hostile, which is the point.
Uint8List buildZip(List<ZipItem> items, {String comment = ''}) {
  final body = BytesBuilder();
  final central = BytesBuilder();

  for (final item in items) {
    final name = utf8.encode(item.name);
    final raw = item.data;
    final useDeflate = item.deflate && raw.isNotEmpty;
    final stored = useDeflate ? ZLibCodec(raw: true).encode(raw) : raw;
    final method = useDeflate ? 8 : 0;
    final crc = item.crcOverride ?? crc32(raw);
    final uncompressed = item.declaredSizeOverride ?? raw.length;
    final offset = body.length;

    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, stored.length, Endian.little)
      ..setUint32(22, uncompressed, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    body
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(stored);

    final entry = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, method, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, stored.length, Endian.little)
      ..setUint32(24, uncompressed, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(entry.buffer.asUint8List())
      ..add(name);
  }

  final centralOffset = body.length;
  final commentBytes = utf8.encode(comment);
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, items.length, Endian.little)
    ..setUint16(10, items.length, Endian.little)
    ..setUint32(12, central.length, Endian.little)
    ..setUint32(16, centralOffset, Endian.little)
    ..setUint16(20, commentBytes.length, Endian.little);

  return (BytesBuilder()
        ..add(body.toBytes())
        ..add(central.toBytes())
        ..add(end.buffer.asUint8List())
        ..add(commentBytes))
      .toBytes();
}

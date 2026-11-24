import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'zip_reader.dart';

/// Packs the files under [directory] into a ZIP archive held in memory, with
/// nothing compressed.
///
/// It exists so that an unpacked extension folder can take exactly the path an
/// `.xpi` does, rather than a second install route that could behave
/// differently. Entry names use `/` and are relative to [directory].
Future<Uint8List> zipDirectory(Directory directory) async {
  final root = directory.absolute.path;
  final entries = <_Entry>[];

  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;

    var relative = entity.absolute.path.substring(root.length);
    while (relative.startsWith(Platform.pathSeparator)) {
      relative = relative.substring(1);
    }
    final name = relative.replaceAll(Platform.pathSeparator, '/');

    // Editors and the OS leave droppings that are no part of an extension.
    final segments = name.split('/');
    if (segments.any(
      (s) => s == '.git' || s == '.DS_Store' || s == 'node_modules',
    )) {
      continue;
    }

    entries.add(_Entry(name, await entity.readAsBytes()));
  }

  entries.sort((a, b) => a.name.compareTo(b.name));
  return _write(entries);
}

class _Entry {
  _Entry(this.name, this.data);

  final String name;
  final Uint8List data;
}

Uint8List _write(List<_Entry> entries) {
  final body = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);

  for (final entry in entries) {
    final name = utf8.encode(entry.name);
    final crc = crc32(entry.data);
    final offset = body.length;

    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800, Endian.little) // names are UTF-8
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, entry.data.length, Endian.little)
      ..setUint32(22, entry.data.length, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    body
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(entry.data);

    final header = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, entry.data.length, Endian.little)
      ..setUint32(24, entry.data.length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(header.buffer.asUint8List())
      ..add(name);
  }

  final centralOffset = body.length;
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, central.length, Endian.little)
    ..setUint32(16, centralOffset, Endian.little);

  return (BytesBuilder(copy: false)
        ..add(body.takeBytes())
        ..add(central.takeBytes())
        ..add(end.buffer.asUint8List()))
      .takeBytes();
}

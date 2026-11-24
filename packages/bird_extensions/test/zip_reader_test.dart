import 'dart:convert';
import 'dart:typed_data';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

import 'support/zip_builder.dart';

void main() {
  group('ZipArchive', () {
    test('reads stored and deflated entries', () {
      final zip = buildZip([
        ZipItem.text('a.txt', 'hello ' * 100),
        ZipItem.text('b.txt', 'stored', deflate: false),
        ZipItem('dir/', const []),
      ]);

      final archive = ZipArchive.fromBytes(zip);
      expect(archive.entries.map((e) => e.name), ['a.txt', 'b.txt', 'dir/']);
      expect(archive.entries[0].method, 8);
      expect(archive.entries[1].method, 0);
      expect(archive.entries[2].isDirectory, isTrue);

      expect(utf8.decode(archive.read(archive.find('a.txt')!)), 'hello ' * 100);
      expect(utf8.decode(archive.read(archive.find('b.txt')!)), 'stored');
      expect(archive.read(archive.find('dir/')!), isEmpty);
    });

    test('finds the end record behind a trailing comment', () {
      final zip = buildZip([ZipItem.text('a', 'x')], comment: 'made by test');
      expect(ZipArchive.fromBytes(zip).entries, hasLength(1));
    });

    test('rejects input that is not a ZIP', () {
      expect(
        () => ZipArchive.fromBytes(Uint8List.fromList(List.filled(100, 7))),
        throwsA(isA<ZipFormatException>()),
      );
      expect(
        () => ZipArchive.fromBytes(Uint8List(5)),
        throwsA(isA<ZipFormatException>()),
      );
    });

    test('rejects a truncated archive', () {
      final zip = buildZip([ZipItem.text('a', 'x' * 500)]);
      final truncated = Uint8List.sublistView(zip, 0, zip.length - 30);
      expect(
        () => ZipArchive.fromBytes(truncated),
        throwsA(isA<ZipFormatException>()),
      );
    });

    test('rejects duplicate names', () {
      final zip = buildZip([ZipItem.text('a', '1'), ZipItem.text('a', '2')]);
      expect(
        () => ZipArchive.fromBytes(zip),
        throwsA(
          isA<ZipFormatException>().having(
            (e) => e.message,
            'message',
            contains('Duplicate'),
          ),
        ),
      );
    });

    test('fails the CRC check on corrupted contents', () {
      final zip = buildZip([ZipItem('a', utf8.encode('abc'), crcOverride: 1)]);
      final archive = ZipArchive.fromBytes(zip);
      expect(
        () => archive.read(archive.entries.single),
        throwsA(
          isA<ZipFormatException>().having(
            (e) => e.message,
            'message',
            contains('CRC'),
          ),
        ),
      );
    });

    test('refuses an entry that inflates past its declared size', () {
      // Claims 100 bytes, inflates to a megabyte.
      final zip = buildZip([
        ZipItem('bomb', Uint8List(1024 * 1024), declaredSizeOverride: 100),
      ]);
      final archive = ZipArchive.fromBytes(zip);
      expect(
        () => archive.read(archive.entries.single),
        throwsA(isA<ZipFormatException>()),
      );
    });

    test('refuses an entry over the size limit before inflating', () {
      final zip = buildZip([ZipItem('big', Uint8List(4096))]);
      final archive = ZipArchive.fromBytes(zip);
      expect(
        () => archive.read(archive.entries.single, maxBytes: 100),
        throwsA(isA<ZipFormatException>()),
      );
    });
  });

  test('crc32 matches the known check value', () {
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  });
}

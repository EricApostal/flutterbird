import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

import 'support/zip_builder.dart';

void main() {
  group('safeRelativePath', () {
    test('accepts ordinary paths and normalizes them', () {
      expect(safeRelativePath('a/b.js'), 'a/b.js');
      expect(safeRelativePath('a//b/./c.js'), 'a/b/c.js');
      expect(safeRelativePath('dir/'), 'dir');
    });

    test('rejects anything that could leave the directory', () {
      for (final name in [
        '',
        '/etc/passwd',
        '../evil',
        'a/../../evil',
        'a/..',
        r'a\b',
        r'..\evil',
        'C:/evil',
        'c:evil',
        'nul\u0000.js',
      ]) {
        expect(safeRelativePath(name), isNull, reason: name);
      }
    });
  });

  group('extractArchive', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('bird_extract_');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    test('writes files, creates directories and skips META-INF', () async {
      final archive = ZipArchive.fromBytes(
        buildZip([
          ZipItem.text('manifest.json', '{}'),
          ZipItem.text('js/content.js', 'console.log(1)'),
          ZipItem('empty/', const []),
          ZipItem.text('META-INF/mozilla.rsa', 'signature'),
        ]),
      );

      final written = await extractArchive(archive, temp);

      expect(written, ['manifest.json', 'js/content.js']);
      expect(
        File('${temp.path}/js/content.js').readAsStringSync(),
        'console.log(1)',
      );
      expect(Directory('${temp.path}/empty').existsSync(), isTrue);
      expect(Directory('${temp.path}/META-INF').existsSync(), isFalse);
    });

    test('refuses a path traversal and writes nothing outside', () async {
      final inner = Directory('${temp.path}/inner')..createSync();
      final archive = ZipArchive.fromBytes(
        buildZip([ZipItem.text('../escaped.txt', 'pwned')]),
      );

      await expectLater(
        extractArchive(archive, inner),
        throwsA(isA<ZipFormatException>()),
      );
      expect(File('${temp.path}/escaped.txt').existsSync(), isFalse);
    });

    test('refuses names that differ only by case', () async {
      final archive = ZipArchive.fromBytes(
        buildZip([ZipItem.text('a.js', '1'), ZipItem.text('A.js', '2')]),
      );
      await expectLater(
        extractArchive(archive, temp),
        throwsA(isA<ZipFormatException>()),
      );
    });

    test('enforces the total size limit', () async {
      final archive = ZipArchive.fromBytes(
        buildZip([ZipItem.text('a', 'x' * 600), ZipItem.text('b', 'y' * 600)]),
      );
      await expectLater(
        extractArchive(
          archive,
          temp,
          limits: const ExtractionLimits(maxTotalBytes: 1000),
        ),
        throwsA(isA<ZipFormatException>()),
      );
    });
  });
}

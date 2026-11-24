import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

void main() {
  test('orders versions like Mozilla does', () {
    // Each list is ascending.
    const ordered = [
      ['1.0pre1', '1.0pre2', '1.0', '1.0.1', '1.1', '1.10', '2.0'],
      ['0.9', '1.0a1', '1.0b1', '1.0'],
      ['1.9', '1.10'],
    ];
    for (final versions in ordered) {
      for (var i = 0; i < versions.length - 1; i++) {
        expect(
          compareVersions(versions[i], versions[i + 1]),
          lessThan(0),
          reason: '${versions[i]} < ${versions[i + 1]}',
        );
        expect(
          compareVersions(versions[i + 1], versions[i]),
          greaterThan(0),
          reason: '${versions[i + 1]} > ${versions[i]}',
        );
      }
    }
  });

  test('treats missing trailing zeros as equal', () {
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('2', '2.0.0.0'), 0);
  });

  test('plus bumps the number before it', () {
    expect(compareVersions('1.0+', '1.0'), greaterThan(0));
    expect(compareVersions('1.0+', '1.1'), 0);
  });

  test('star is infinitely large', () {
    expect(compareVersions('1.*', '1.99999'), greaterThan(0));
  });
}

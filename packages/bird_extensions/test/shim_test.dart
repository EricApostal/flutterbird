import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

import 'support/node_world.dart';

void main() {
  test('the embedded shim is the current browser_shim.js', () {
    final file = File('lib/src/shim/browser_shim.js').readAsStringSync();
    expect(
      browserShimSource,
      file,
      reason: 'run `dart run tool/embed_shim.dart` after editing the shim',
    );
  });

  test('the shim passes its tests under Node', () async {
    final result = await Process.run('node', [
      '--test',
      'test/shim/shim_test.js',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, skip: hasNode ? null : 'needs node');
}

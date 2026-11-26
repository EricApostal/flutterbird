import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;
  late File file;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bird_pins_');
    file = File('${temp.path}/toolbar.json');
  });

  tearDown(() => temp.delete(recursive: true));

  test('an extension starts unpinned unless it asked for the toolbar', () async {
    final pins = await ToolbarPins.open(file);
    await pins.introduce('a', onToolbar: false);
    await pins.introduce('b', onToolbar: true);
    expect(pins.pinned, ['b']);
    await pins.dispose();
  });

  test('what the user chose outlasts being introduced again', () async {
    var pins = await ToolbarPins.open(file);
    await pins.introduce('a', onToolbar: false);
    await pins.introduce('b', onToolbar: true);
    await pins.setPinned('a', pinned: true);
    await pins.setPinned('b', pinned: false);
    await pins.dispose();

    pins = await ToolbarPins.open(file);
    await pins.introduce('a', onToolbar: false);
    await pins.introduce('b', onToolbar: true);
    expect(pins.pinned, ['a']);
    await pins.dispose();
  });

  test('buttons keep the order they were pinned in', () async {
    final pins = await ToolbarPins.open(file);
    for (final uuid in ['c', 'a', 'b']) {
      await pins.setPinned(uuid, pinned: true);
    }
    await pins.setPinned('a', pinned: true);
    expect(pins.pinned, ['c', 'a', 'b']);
    await pins.dispose();
    expect((await ToolbarPins.open(file)).pinned, ['c', 'a', 'b']);
  });

  test('installing again after uninstalling starts over', () async {
    final pins = await ToolbarPins.open(file);
    await pins.setPinned('a', pinned: true);
    await pins.forget('a');
    expect(pins.pinned, isEmpty);
    await pins.introduce('a', onToolbar: true);
    expect(pins.pinned, ['a']);
    await pins.dispose();
  });

  test('changes are announced, and only real ones', () async {
    final pins = await ToolbarPins.open(file);
    var changes = 0;
    pins.changes.listen((_) => changes++);
    await pins.setPinned('a', pinned: true);
    await pins.setPinned('a', pinned: true);
    await pins.forget('nothing');
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    await pins.dispose();
  });

  test('a damaged file reads as nothing decided', () async {
    await file.writeAsString('{not json');
    final pins = await ToolbarPins.open(file);
    expect(pins.pinned, isEmpty);
    await pins.setPinned('a', pinned: true);
    await pins.dispose();
    expect((await ToolbarPins.open(file)).pinned, ['a']);
  });
}

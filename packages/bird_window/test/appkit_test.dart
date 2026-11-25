// Checks the AppKit calls against the AppKit that is running. Windows can only
// be made on the main thread, which a test does not run on, so nothing here
// makes one: it checks that the selectors exist and that the calls that are
// about no window in particular give sensible answers.
@TestOn('mac-os')
library;

import 'package:bird_window/bird_window.dart';
import 'package:bird_window/src/macos/objc.dart';
import 'package:test/test.dart';

void main() {
  test('every instance selector used is one its class answers', () {
    for (final entry in instanceSelectorsUsed.entries) {
      for (final name in entry.value) {
        expect(
          msgBoolSel(
            objcClass(entry.key),
            selector('instancesRespondToSelector:'),
            selector(name),
          ),
          isTrue,
          reason: '-[${entry.key} $name]',
        );
      }
    }
  });

  test('every class selector used is one its class answers', () {
    for (final entry in classSelectorsUsed.entries) {
      for (final name in entry.value) {
        expect(
          msgBoolSel(
            objcClass(entry.key),
            selector('respondsToSelector:'),
            selector(name),
          ),
          isTrue,
          reason: '+[${entry.key} $name]',
        );
      }
    }
  });

  test('screens come back with y measured down from the primary one', () {
    final screens = MacDesktop.screens();
    // A machine with no window server session has no screens to describe.
    if (screens.isEmpty) {
      markTestSkipped('no screens');
      return;
    }

    final primary = screens.first;
    expect(primary.frame.topLeft, ScreenPoint.zero);
    expect(primary.frame.width, greaterThan(0));
    expect(primary.frame.height, greaterThan(0));
    // The menu bar is at the top, so the usable area starts below it and ends
    // no lower than the screen does.
    expect(primary.visibleFrame.top, greaterThanOrEqualTo(0));
    expect(
      primary.visibleFrame.bottom,
      lessThanOrEqualTo(primary.frame.bottom),
    );
    expect(
      MacDesktop.visibleFrameAt(primary.frame.center),
      primary.visibleFrame,
    );
  });

  test('the mouse can be read', () {
    if (MacDesktop.screens().isEmpty) {
      markTestSkipped('no screens');
      return;
    }
    final cursor = MacDesktop.cursorPosition();
    expect(cursor.x.isFinite, isTrue);
    expect(cursor.y.isFinite, isTrue);
    MacDesktop.primaryButtonDown();
  });
}

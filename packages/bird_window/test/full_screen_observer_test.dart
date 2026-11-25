// The observer hears AppKit's notifications through a class made at run time.
// Posting them here, with a plain object standing in for a window, runs that
// whole path.
@TestOn('mac-os')
library;

import 'package:bird_window/src/macos/full_screen_observer.dart';
import 'package:bird_window/src/macos/objc.dart';
import 'package:test/test.dart';

Id makeObject() =>
    msgId(msgId(objcClass('NSObject'), selector('alloc')), selector('init'));

/// Lets what was posted arrive: it comes as a later event.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

void main() {
  test('says when its own window has entered and left full screen', () async {
    final window = makeObject();
    final other = makeObject();
    final heard = <bool>[];
    final othersHeard = <bool>[];
    final observer = MacFullScreenObserver(window, heard.add);
    final otherObserver = MacFullScreenObserver(other, othersHeard.add);

    postNotification(didEnterFullScreen, window);
    await settle();
    expect(heard, [true]);

    postNotification(didExitFullScreen, window);
    await settle();
    expect(heard, [true, false]);
    expect(othersHeard, isEmpty);

    observer.dispose();
    postNotification(didEnterFullScreen, window);
    await settle();
    expect(heard, [true, false]);

    otherObserver.dispose();
    observer.dispose();
  });
}

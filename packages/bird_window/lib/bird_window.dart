/// Native window control for FlutterBird.
///
/// All coordinates are global screen coordinates in logical points, with the
/// origin at the top left of the primary screen and y pointing down, as in
/// Flutter. AppKit's own origin is the bottom left; the conversion happens
/// inside this package.
library;

export 'src/geometry.dart';
export 'src/macos/full_screen_observer.dart' show MacFullScreenObserver;
export 'src/macos/mac_window.dart';

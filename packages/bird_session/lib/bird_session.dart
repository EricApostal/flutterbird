/// The browser's window bookkeeping: which tabs are in which window, how a tab
/// dragged between windows moves, and where new windows go.
library;

export 'package:bird_window/bird_window.dart'
    show ScreenPoint, ScreenRect, ScreenSize;

export 'src/browser_session.dart';
export 'src/key_claims.dart';
export 'src/tab_drag.dart';
export 'src/window_placement.dart';

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../geometry.dart';
import 'objc.dart';

// NSWindowStyleMask.
const int _fullScreenMask = 1 << 14;
const int _fullSizeContentViewMask = 1 << 15;

// NSWindowTitleVisibility.
const int _titleHidden = 1;

// NSEventType.
const int _leftMouseDown = 1;
const int _leftMouseDragged = 6;

/// The selectors this package sends, by the class that has to answer them.
/// A test checks these against the running AppKit, since a misspelt one would
/// otherwise only show as a crash in the app.
const Map<String, List<String>> instanceSelectorsUsed = {
  'NSWindow': [
    'windowNumber',
    'frame',
    'contentRectForFrameRect:',
    'setFrame:display:',
    'setFrameTopLeftPoint:',
    'styleMask',
    'setStyleMask:',
    'setTitlebarAppearsTransparent:',
    'setTitleVisibility:',
    'setMovable:',
    'setAlphaValue:',
    'setIgnoresMouseEvents:',
    'makeKeyAndOrderFront:',
    'orderOut:',
    'isKeyWindow',
    'isVisible',
    'performWindowDragWithEvent:',
    'zoom:',
    'screen',
  ],
  'NSScreen': ['frame', 'visibleFrame'],
  'NSArray': ['count', 'objectAtIndex:'],
  'NSEvent': ['type'],
  'NSApplication': ['currentEvent'],
};

const Map<String, List<String>> classSelectorsUsed = {
  'NSEvent': ['mouseLocation', 'pressedMouseButtons'],
  'NSScreen': ['screens'],
  'NSWindow': ['windowNumberAtPoint:belowWindowWithWindowNumber:'],
  'NSApplication': ['sharedApplication'],
};

List<Id> _screens() {
  final array = msgId(objcClass('NSScreen'), selector('screens'));
  if (array == nullptr) return const [];
  final count = msgInt(array, selector('count'));
  return [
    for (var i = 0; i < count; i++)
      msgIdUint(array, selector('objectAtIndex:'), i),
  ];
}

/// The height AppKit measures y up from: that of the screen with the menu bar,
/// which is always the first one.
double _primaryScreenHeight() {
  final screens = _screens();
  if (screens.isEmpty) return 0;
  return msgRect(screens.first, selector('frame')).size.height;
}

ScreenRect _fromAppKit(CGRect rect, double primaryHeight) => ScreenRect(
  rect.origin.x,
  primaryHeight - (rect.origin.y + rect.size.height),
  rect.size.width,
  rect.size.height,
);

/// Allocates a struct for the length of [body].
T _withRect<T>(ScreenRect rect, double primaryHeight, T Function(CGRect) body) {
  final pointer = calloc<CGRect>();
  try {
    pointer.ref.origin.x = rect.left;
    pointer.ref.origin.y = primaryHeight - rect.bottom;
    pointer.ref.size.width = rect.width;
    pointer.ref.size.height = rect.height;
    return body(pointer.ref);
  } finally {
    calloc.free(pointer);
  }
}

T _withPoint<T>(double x, double y, T Function(CGPoint) body) {
  final pointer = calloc<CGPoint>();
  try {
    pointer.ref.x = x;
    pointer.ref.y = y;
    return body(pointer.ref);
  } finally {
    calloc.free(pointer);
  }
}

/// A screen: all of it, and the part the menu bar and the Dock leave free.
final class MacScreen {
  const MacScreen({required this.frame, required this.visibleFrame});

  final ScreenRect frame;
  final ScreenRect visibleFrame;

  @override
  String toString() => 'MacScreen(frame: $frame, visible: $visibleFrame)';
}

/// What AppKit knows that is about no window in particular: the screens, the
/// mouse, and which window is on top where.
abstract final class MacDesktop {
  static List<MacScreen> screens() => withPool(() {
    final primaryHeight = _primaryScreenHeight();
    return [
      for (final screen in _screens())
        MacScreen(
          frame: _fromAppKit(msgRect(screen, selector('frame')), primaryHeight),
          visibleFrame: _fromAppKit(
            msgRect(screen, selector('visibleFrame')),
            primaryHeight,
          ),
        ),
    ];
  });

  /// The usable area of the screen [point] is on, or of the nearest one.
  static ScreenRect visibleFrameAt(ScreenPoint point) {
    final all = screens();
    if (all.isEmpty) return const ScreenRect(0, 0, 1440, 900);

    var nearest = all.first;
    var nearestDistance = double.infinity;
    for (final screen in all) {
      if (screen.frame.contains(point)) return screen.visibleFrame;
      final delta = screen.frame.center - point;
      final distance = delta.x * delta.x + delta.y * delta.y;
      if (distance < nearestDistance) {
        nearest = screen;
        nearestDistance = distance;
      }
    }
    return nearest.visibleFrame;
  }

  /// Where the mouse is, whether or not one of the app's windows is under it.
  static ScreenPoint cursorPosition() => withPool(() {
    final location = msgPoint(objcClass('NSEvent'), selector('mouseLocation'));
    return ScreenPoint(location.x, _primaryScreenHeight() - location.y);
  });

  /// Whether the primary mouse button is down right now.
  static bool primaryButtonDown() =>
      msgInt(objcClass('NSEvent'), selector('pressedMouseButtons')) & 1 != 0;

  /// The window server's number of the frontmost window at [point], which can
  /// belong to another app, or 0 for none. With [below], only windows under
  /// that one are looked at.
  static int windowNumberAt(ScreenPoint point, {int below = 0}) => withPool(() {
    return _withPoint(
      point.x,
      _primaryScreenHeight() - point.y,
      (appKitPoint) => msgIntPointInt(
        objcClass('NSWindow'),
        selector('windowNumberAtPoint:belowWindowWithWindowNumber:'),
        appKitPoint,
        below,
      ),
    );
  });
}

/// One `NSWindow`, by its pointer.
///
/// The pointer is only good while the window lives: whoever destroys the window
/// has to stop using this. Every method has to be called on the main thread,
/// which is the thread Flutter runs Dart on when windowing is enabled.
final class MacWindow {
  MacWindow(this.handle) {
    if (handle == nullptr) {
      throw ArgumentError('A MacWindow needs an NSWindow');
    }
  }

  final Pointer<Void> handle;

  int get windowNumber => msgInt(handle, selector('windowNumber'));

  int get _styleMask => msgInt(handle, selector('styleMask'));

  bool get isFullScreen => _styleMask & _fullScreenMask != 0;

  bool get isKey => msgBool(handle, selector('isKeyWindow'));

  /// Whether the window is on screen. A window Flutter has just made is not,
  /// until it has drawn its first frame.
  bool get isVisible => msgBool(handle, selector('isVisible'));

  /// The whole window, title bar included.
  ScreenRect get frame => withPool(
    () =>
        _fromAppKit(msgRect(handle, selector('frame')), _primaryScreenHeight()),
  );

  set frame(ScreenRect value) => withPool(() {
    _withRect(value, _primaryScreenHeight(), (rect) {
      msgVoidRectBool(handle, selector('setFrame:display:'), rect, true);
    });
  });

  /// The part of the window the app draws in.
  ScreenRect get contentRect => withPool(() {
    final content = msgRectRect(
      handle,
      selector('contentRectForFrameRect:'),
      msgRect(handle, selector('frame')),
    );
    return _fromAppKit(content, _primaryScreenHeight());
  });

  /// The usable area of the screen the window is on.
  ScreenRect get visibleScreenFrame => withPool(() {
    final screen = msgId(handle, selector('screen'));
    if (screen == nullptr) {
      return MacDesktop.visibleFrameAt(frame.center);
    }
    return _fromAppKit(
      msgRect(screen, selector('visibleFrame')),
      _primaryScreenHeight(),
    );
  });

  void moveTo(ScreenPoint topLeft) => withPool(() {
    _withPoint(topLeft.x, _primaryScreenHeight() - topLeft.y, (point) {
      msgVoidPoint(handle, selector('setFrameTopLeftPoint:'), point);
    });
  });

  /// Lets the app draw where the title bar is. The traffic lights stay, and the
  /// window then only moves when [startDrag] is called, so that dragging a tab
  /// does not drag the window.
  void useHiddenTitleBar() {
    msgVoidInt(
      handle,
      selector('setStyleMask:'),
      _styleMask | _fullSizeContentViewMask,
    );
    msgVoidBool(handle, selector('setTitlebarAppearsTransparent:'), true);
    msgVoidInt(handle, selector('setTitleVisibility:'), _titleHidden);
    msgVoidBool(handle, selector('setMovable:'), false);
  }

  /// Takes the window out of sight and out of the mouse's way without taking it
  /// off screen. It keeps drawing, and a mouse drag that started in it keeps
  /// being reported to it, neither of which is true of an ordered-out window.
  void setParked(bool parked) {
    msgVoidDouble(handle, selector('setAlphaValue:'), parked ? 0 : 1);
    msgVoidBool(handle, selector('setIgnoresMouseEvents:'), parked);
  }

  void makeKeyAndOrderFront() {
    msgVoidId(handle, selector('makeKeyAndOrderFront:'), nullptr);
  }

  void orderOut() {
    msgVoidId(handle, selector('orderOut:'), nullptr);
  }

  /// Hands the mouse drag in progress to AppKit, which moves the window with it
  /// the way dragging a title bar does. Does nothing unless the app is in the
  /// middle of a press or a drag.
  bool startDrag() => withPool(() {
    final app = msgId(
      objcClass('NSApplication'),
      selector('sharedApplication'),
    );
    final event = msgId(app, selector('currentEvent'));
    if (event == nullptr) return false;

    final type = msgInt(event, selector('type'));
    if (type != _leftMouseDown && type != _leftMouseDragged) return false;

    msgVoidId(handle, selector('performWindowDragWithEvent:'), event);
    return true;
  });

  /// What double clicking a title bar does.
  void zoom() {
    msgVoidId(handle, selector('zoom:'), nullptr);
  }
}

/// Hearing when a window has finished going into or out of full screen.
///
/// macOS animates the change, and a page waiting for it must not be told until
/// the animation is over. AppKit says so with a notification, which is taken
/// here by a class made at run time, so that there is still nothing to compile.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'objc.dart';

const String _className = 'BirdFullScreenObserver';
const String didEnterFullScreen = 'NSWindowDidEnterFullScreenNotification';
const String didExitFullScreen = 'NSWindowDidExitFullScreenNotification';
const String _enterSelector = 'birdDidEnterFullScreen:';
const String _exitSelector = 'birdDidExitFullScreen:';

typedef _ActionNative = Void Function(Id self, Sel command, Id notification);

final DynamicLibrary _runtime = DynamicLibrary.process();

final Id Function(Id, Pointer<Utf8>, int) _allocateClassPair = _runtime
    .lookupFunction<
      Id Function(Id, Pointer<Utf8>, IntPtr),
      Id Function(Id, Pointer<Utf8>, int)
    >('objc_allocateClassPair');

final void Function(Id) _registerClassPair = _runtime
    .lookupFunction<Void Function(Id), void Function(Id)>(
      'objc_registerClassPair',
    );

final bool Function(
  Id,
  Sel,
  Pointer<NativeFunction<_ActionNative>>,
  Pointer<Utf8>,
)
_addMethod = _runtime
    .lookupFunction<
      Bool Function(
        Id,
        Sel,
        Pointer<NativeFunction<_ActionNative>>,
        Pointer<Utf8>,
      ),
      bool Function(
        Id,
        Sel,
        Pointer<NativeFunction<_ActionNative>>,
        Pointer<Utf8>,
      )
    >('class_addMethod');

final Id Function(Pointer<Utf8>) _lookUpClass = _runtime
    .lookupFunction<Id Function(Pointer<Utf8>), Id Function(Pointer<Utf8>)>(
      'objc_lookUpClass',
    );

final Pointer<NativeFunction<Void Function()>> _msgSend = _runtime
    .lookup<NativeFunction<Void Function()>>('objc_msgSend');

final _msgIdUtf8 = _msgSend
    .cast<NativeFunction<Id Function(Id, Sel, Pointer<Utf8>)>>()
    .asFunction<Id Function(Id, Sel, Pointer<Utf8>)>();

final _msgAddObserver = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel, Id, Sel, Id, Id)>>()
    .asFunction<void Function(Id, Sel, Id, Sel, Id, Id)>();

final _msgPost = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel, Id, Id)>>()
    .asFunction<void Function(Id, Sel, Id, Id)>();

/// An autoreleased `NSString`.
Id _string(String value) {
  final pointer = value.toNativeUtf8();
  try {
    return _msgIdUtf8(
      objcClass('NSString'),
      selector('stringWithUTF8String:'),
      pointer,
    );
  } finally {
    malloc.free(pointer);
  }
}

Id _notificationCenter() =>
    msgId(objcClass('NSNotificationCenter'), selector('defaultCenter'));

/// Posts a notification as AppKit would, for tests.
void postNotification(String name, Pointer<Void> sender) => withPool(() {
  _msgPost(
    _notificationCenter(),
    selector('postNotificationName:object:'),
    _string(name),
    sender,
  );
});

/// Tells [onChange] each time one window has finished entering (true) or
/// leaving (false) full screen.
///
/// What it is told arrives as a later event on this isolate, not from inside
/// AppKit's own call.
final class MacFullScreenObserver {
  MacFullScreenObserver(Pointer<Void> window, this.onChange) {
    _observer = msgId(
      msgId(_observerClass, selector('alloc')),
      selector('init'),
    );
    _observers[_observer.address] = this;

    withPool(() {
      for (final (name, action) in const [
        (didEnterFullScreen, _enterSelector),
        (didExitFullScreen, _exitSelector),
      ]) {
        _msgAddObserver(
          _notificationCenter(),
          selector('addObserver:selector:name:object:'),
          _observer,
          selector(action),
          _string(name),
          window,
        );
      }
    });
  }

  final void Function(bool isFullScreen) onChange;
  late final Id _observer;
  bool _disposed = false;

  /// Must be called before the window is destroyed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _observers.remove(_observer.address);
    withPool(() {
      msgVoidId(_notificationCenter(), selector('removeObserver:'), _observer);
    });
    msgVoid(_observer, selector('release'));
  }

  static final Map<int, MacFullScreenObserver> _observers = {};

  static void _entered(Id self, Sel command, Id notification) =>
      _observers[self.address]?.onChange(true);

  static void _exited(Id self, Sel command, Id notification) =>
      _observers[self.address]?.onChange(false);

  // `listener` callables can be called from any thread and with no isolate
  // entered, which is how AppKit calls. Their arguments arrive later, so only
  // the receiver's address is looked at, and nothing is read through them.
  static final NativeCallable<_ActionNative> _enterCallable =
      NativeCallable<_ActionNative>.listener(_entered)
        ..keepIsolateAlive = false;
  static final NativeCallable<_ActionNative> _exitCallable =
      NativeCallable<_ActionNative>.listener(_exited)..keepIsolateAlive = false;

  static final Id _observerClass = _makeClass();

  static Id _makeClass() {
    final types = 'v@:@'.toNativeUtf8();
    try {
      // A class can only be made once in a process, and a hot restart makes
      // this isolate again in the same one. The old class would go on calling
      // the old isolate, so each isolate gets a class of its own.
      var attempt = 0;
      var candidate = _className;
      while (true) {
        final candidateName = candidate.toNativeUtf8();
        final taken = _lookUpClass(candidateName) != nullptr;
        malloc.free(candidateName);
        if (!taken) break;
        candidate = '$_className${++attempt}';
      }

      final uniqueName = candidate.toNativeUtf8();
      final made = _allocateClassPair(objcClass('NSObject'), uniqueName, 0);
      malloc.free(uniqueName);
      if (made == nullptr) {
        throw StateError('Could not make the class $candidate');
      }
      _addMethod(
        made,
        selector(_enterSelector),
        _enterCallable.nativeFunction,
        types,
      );
      _addMethod(
        made,
        selector(_exitSelector),
        _exitCallable.nativeFunction,
        types,
      );
      _registerClassPair(made);
      return made;
    } finally {
      malloc.free(types);
    }
  }
}

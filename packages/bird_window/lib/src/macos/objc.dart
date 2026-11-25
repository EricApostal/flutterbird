/// The little of the Objective-C runtime that calling AppKit needs.
///
/// `objc_msgSend` has no signature of its own: it is cast to the signature of
/// the method being called, one typed alias here per shape used. Structs are
/// returned the ordinary way, which is right on arm64 (the only architecture
/// FlutterBird builds for); x86_64 would need `objc_msgSend_stret` for the
/// rectangle returns.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef Id = Pointer<Void>;
typedef Sel = Pointer<Void>;

final class CGPoint extends Struct {
  @Double()
  external double x;

  @Double()
  external double y;
}

final class CGSize extends Struct {
  @Double()
  external double width;

  @Double()
  external double height;
}

final class CGRect extends Struct {
  external CGPoint origin;
  external CGSize size;
}

final DynamicLibrary _runtime = DynamicLibrary.process();

/// AppKit is already in the process in the app; a plain Dart test has to load it.
final DynamicLibrary appKit = DynamicLibrary.open(
  '/System/Library/Frameworks/AppKit.framework/AppKit',
);

final Id Function(Pointer<Utf8>) _getClass = _runtime
    .lookupFunction<Id Function(Pointer<Utf8>), Id Function(Pointer<Utf8>)>(
      'objc_getClass',
    );

final Sel Function(Pointer<Utf8>) _registerName = _runtime
    .lookupFunction<Sel Function(Pointer<Utf8>), Sel Function(Pointer<Utf8>)>(
      'sel_registerName',
    );

final Id Function() autoreleasePoolPush = _runtime
    .lookupFunction<Id Function(), Id Function()>('objc_autoreleasePoolPush');

final void Function(Id) autoreleasePoolPop = _runtime
    .lookupFunction<Void Function(Id), void Function(Id)>(
      'objc_autoreleasePoolPop',
    );

/// Runs [body] with a pool of its own, so that what AppKit hands back
/// autoreleased does not pile up while something polls.
T withPool<T>(T Function() body) {
  final pool = autoreleasePoolPush();
  try {
    return body();
  } finally {
    autoreleasePoolPop(pool);
  }
}

final Map<String, Id> _classes = {};
final Map<String, Sel> _selectors = {};

Id objcClass(String name) => _classes.putIfAbsent(name, () {
  // Looking AppKit up first makes sure its classes are registered.
  appKit.handle;
  final pointer = name.toNativeUtf8();
  try {
    final result = _getClass(pointer);
    if (result == nullptr) {
      throw StateError('There is no Objective-C class named $name');
    }
    return result;
  } finally {
    malloc.free(pointer);
  }
});

Sel selector(String name) => _selectors.putIfAbsent(name, () {
  final pointer = name.toNativeUtf8();
  try {
    return _registerName(pointer);
  } finally {
    malloc.free(pointer);
  }
});

final Pointer<NativeFunction<Void Function()>> _msgSend = _runtime
    .lookup<NativeFunction<Void Function()>>('objc_msgSend');

// Returning values.

final msgId = _msgSend
    .cast<NativeFunction<Id Function(Id, Sel)>>()
    .asFunction<Id Function(Id, Sel)>();

final msgInt = _msgSend
    .cast<NativeFunction<Int64 Function(Id, Sel)>>()
    .asFunction<int Function(Id, Sel)>();

final msgBool = _msgSend
    .cast<NativeFunction<Bool Function(Id, Sel)>>()
    .asFunction<bool Function(Id, Sel)>();

final msgPoint = _msgSend
    .cast<NativeFunction<CGPoint Function(Id, Sel)>>()
    .asFunction<CGPoint Function(Id, Sel)>();

final msgRect = _msgSend
    .cast<NativeFunction<CGRect Function(Id, Sel)>>()
    .asFunction<CGRect Function(Id, Sel)>();

final msgRectRect = _msgSend
    .cast<NativeFunction<CGRect Function(Id, Sel, CGRect)>>()
    .asFunction<CGRect Function(Id, Sel, CGRect)>();

final msgIdUint = _msgSend
    .cast<NativeFunction<Id Function(Id, Sel, Uint64)>>()
    .asFunction<Id Function(Id, Sel, int)>();

final msgBoolSel = _msgSend
    .cast<NativeFunction<Bool Function(Id, Sel, Sel)>>()
    .asFunction<bool Function(Id, Sel, Sel)>();

final msgIntPointInt = _msgSend
    .cast<NativeFunction<Int64 Function(Id, Sel, CGPoint, Int64)>>()
    .asFunction<int Function(Id, Sel, CGPoint, int)>();

// Setting values.

final msgVoid = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel)>>()
    .asFunction<void Function(Id, Sel)>();

final msgVoidId = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel, Id)>>()
    .asFunction<void Function(Id, Sel, Id)>();

final msgVoidInt = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel, Int64)>>()
    .asFunction<void Function(Id, Sel, int)>();

final msgVoidBool = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel, Bool)>>()
    .asFunction<void Function(Id, Sel, bool)>();

final msgVoidDouble = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel, Double)>>()
    .asFunction<void Function(Id, Sel, double)>();

final msgVoidPoint = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel, CGPoint)>>()
    .asFunction<void Function(Id, Sel, CGPoint)>();

final msgVoidRectBool = _msgSend
    .cast<NativeFunction<Void Function(Id, Sel, CGRect, Bool)>>()
    .asFunction<void Function(Id, Sel, CGRect, bool)>();

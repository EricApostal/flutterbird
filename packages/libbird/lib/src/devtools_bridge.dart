import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef _InspectNative = ffi.Void Function(ffi.Int, ffi.Int, ffi.Int);

/// The engine's side of the developer tools: its DevTools server, and what the
/// server needs the browser to say about its views.
class LadybirdDevTools {
  LadybirdDevTools._();

  static final LadybirdDevTools instance = LadybirdDevTools._();

  late final ffi.DynamicLibrary _library = Platform.isAndroid
      ? ffi.DynamicLibrary.open('libengine.so')
      : ffi.DynamicLibrary.process();

  late final _start = _library
      .lookupFunction<ffi.Int Function(), int Function()>('devtools_start');
  late final _stop = _library
      .lookupFunction<ffi.Void Function(), void Function()>('devtools_stop');
  late final _browserId = _library
      .lookupFunction<ffi.Uint64 Function(ffi.Int), int Function(int)>(
        'devtools_browser_id',
      );
  late final _setInspectCallback = _library
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.NativeFunction<_InspectNative>>),
        void Function(ffi.Pointer<ffi.NativeFunction<_InspectNative>>)
      >('set_devtools_inspect_callback');
  late final _inspect = _library
      .lookupFunction<
        ffi.Void Function(ffi.Int, ffi.Int, ffi.Int),
        void Function(int, int, int)
      >('devtools_inspect_element');

  ffi.NativeCallable<_InspectNative>? _callable;
  bool? _available;

  /// Whether the native library has the developer tools' functions. One from
  /// before they existed does not.
  bool get isAvailable => _available ??= () {
    try {
      return _library.providesSymbol('devtools_start');
    } on ArgumentError {
      return false;
    }
  }();

  /// Told when the user chooses "Inspect" in a page's menu while no tools are
  /// connected. The position is in the view's pixels, and goes back to
  /// [inspectElement] once they are.
  void Function(int viewId, int x, int y)? onInspectRequested;

  /// Has "Inspect" offered in page menus.
  void listenForInspectRequests() {
    if (!isAvailable || _callable != null) return;
    final callable = ffi.NativeCallable<_InspectNative>.listener(
      (int viewId, int x, int y) => onInspectRequested?.call(viewId, x, y),
    );
    _setInspectCallback(callable.nativeFunction);
    _callable = callable;
  }

  /// Starts the DevTools server and returns the port it listens on at
  /// 127.0.0.1. It has no authentication: stop it when the tools close.
  int startServer() {
    if (!isAvailable) {
      throw UnsupportedError(
        'This build of the engine has no developer tools support. Rebuild the '
        'native library.',
      );
    }
    final port = _start();
    if (port <= 0) {
      throw StateError('The engine could not start its DevTools server.');
    }
    return port;
  }

  void stopServer() {
    if (isAvailable) _stop();
  }

  /// The number the DevTools server knows a view by, or null.
  int? browserIdFor(int viewId) {
    if (!isAvailable) return null;
    final id = _browserId(viewId);
    return id == 0 ? null : id;
  }

  /// Selects, in the connected tools, the element at a position of a view.
  void inspectElement(int viewId, int x, int y) {
    if (isAvailable) _inspect(viewId, x, y);
  }

  @visibleForTesting
  void debugSetAvailable(bool? value) => _available = value;
}

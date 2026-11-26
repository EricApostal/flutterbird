import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Where a search of a page stands. [current] counts from zero, and [total]
/// is -1 while the engine does not know it.
typedef FindResult = ({int current, int total});

typedef _ResultNative = ffi.Void Function(ffi.Int, ffi.Int, ffi.Int);

/// The engine's find in page.
class LadybirdFind {
  LadybirdFind._();

  static final LadybirdFind instance = LadybirdFind._();

  late final ffi.DynamicLibrary _library = Platform.isAndroid
      ? ffi.DynamicLibrary.open('libengine.so')
      : ffi.DynamicLibrary.process();

  late final _setCallback = _library
      .lookupFunction<
        ffi.Void Function(ffi.Pointer<ffi.NativeFunction<_ResultNative>>),
        void Function(ffi.Pointer<ffi.NativeFunction<_ResultNative>>)
      >('set_find_in_page_callback');
  late final _find = _library
      .lookupFunction<
        ffi.Void Function(ffi.Int, ffi.Pointer<ffi.Char>),
        void Function(int, ffi.Pointer<ffi.Char>)
      >('find_in_page');
  late final _next = _library
      .lookupFunction<ffi.Void Function(ffi.Int), void Function(int)>(
        'find_in_page_next',
      );
  late final _previous = _library
      .lookupFunction<ffi.Void Function(ffi.Int), void Function(int)>(
        'find_in_page_previous',
      );
  late final _end = _library
      .lookupFunction<ffi.Void Function(ffi.Int), void Function(int)>(
        'find_in_page_end',
      );

  final Map<int, ValueNotifier<FindResult?>> _results = {};
  ffi.NativeCallable<_ResultNative>? _callable;
  bool _unavailable = false;

  /// Whether the engine can search, connecting to it the first time. A native
  /// library from before this existed cannot.
  bool get isAvailable {
    if (_callable != null) return true;
    if (_unavailable) return false;

    final callable = ffi.NativeCallable<_ResultNative>.listener(_onResult);
    try {
      _setCallback(callable.nativeFunction);
    } on ArgumentError catch (error) {
      callable.close();
      _unavailable = true;
      debugPrint('Find in page is not in this engine: $error');
      return false;
    }
    _callable = callable;
    return true;
  }

  void _onResult(int viewId, int current, int total) {
    _notifier(viewId).value = (current: current, total: total);
  }

  ValueNotifier<FindResult?> _notifier(int viewId) =>
      _results.putIfAbsent(viewId, () => ValueNotifier(null));

  /// The engine's latest answer for [viewId].
  ValueListenable<FindResult?> results(int viewId) => _notifier(viewId);

  /// Searches the page for [query], highlighting every match.
  void find(int viewId, String query) {
    // What was answered was about other words.
    _notifier(viewId).value = null;
    if (!isAvailable) return;
    using((arena) => _find(viewId, query.toNativeUtf8(allocator: arena).cast()));
  }

  void next(int viewId) {
    if (isAvailable) _next(viewId);
  }

  void previous(int viewId) {
    if (isAvailable) _previous(viewId);
  }

  /// Takes the highlighting away.
  void end(int viewId) {
    _notifier(viewId).value = null;
    if (isAvailable) _end(viewId);
  }
}

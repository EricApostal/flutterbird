import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

final ffi.DynamicLibrary _library = Platform.isAndroid
    ? ffi.DynamicLibrary.open('libengine.so')
    : ffi.DynamicLibrary.process();

/// Removes the page at [url] from the browser's history. Returns whether the
/// engine can: a native library from before this existed cannot.
bool removeHistoryEntry(String url) {
  try {
    final remove = _library
        .lookupFunction<
          ffi.Void Function(ffi.Pointer<ffi.Char>),
          void Function(ffi.Pointer<ffi.Char>)
        >('remove_history_entry');
    using((arena) => remove(url.toNativeUtf8(allocator: arena).cast()));
    return true;
  } on ArgumentError catch (error) {
    debugPrint('This engine cannot remove history: $error');
    return false;
  }
}

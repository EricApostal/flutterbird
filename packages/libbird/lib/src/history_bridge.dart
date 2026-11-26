import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

final ffi.DynamicLibrary _library = Platform.isAndroid
    ? ffi.DynamicLibrary.open('libengine.so')
    : ffi.DynamicLibrary.process();

/// The pages in the history, newest first, at most [limit] of them, as the JSON
/// the engine gives (see `history_entries_json` in engine.h). Empty when there
/// are none, or when the engine is from before it could say.
String historyEntriesJson({int limit = 400}) {
  try {
    final list = _library
        .lookupFunction<
          ffi.Pointer<Utf8> Function(ffi.Int),
          ffi.Pointer<Utf8> Function(int)
        >('history_entries_json');
    final result = list(limit);
    if (result == ffi.nullptr) return '[]';
    final json = result.toDartString();
    malloc.free(result);
    return json;
  } on ArgumentError catch (error) {
    debugPrint('This engine cannot list history: $error');
    return '[]';
  }
}

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

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'package:flutter/services.dart';
import 'package:libbird/src/generated/engine_bindings.g.dart';

class LadybirdController {
  // final MethodChannel _channel = MethodChannel('libbird');
  // late final ffi.DynamicLibrary _lib;
  // late final LibbirdBindings _bindings;
  // int? _textureId;
  // Size? _lastSize;

  LadybirdController() {
    // _lib = ffi.DynamicLibrary.process();
    // _bindings = LibbirdBindings(_lib);

    // _bindings.init_ladybird();
  }

  void navigate(String url) {
    // final ffi.Pointer<Utf8> charPointer = url.toNativeUtf8();
    // _bindings.navigate_to(charPointer.cast<ffi.Char>());
    // malloc.free(charPointer);
  }
}

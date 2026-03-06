import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'package:flutter/services.dart';
import 'package:ladybird/src/generated/engine_bindings.g.dart';

class LadybirdController {
  final MethodChannel _channel = MethodChannel('libbird');
  late final ffi.DynamicLibrary _lib;
  late final LibbirdBindings _bindings;
  // I'm not entirely sure where I should set the texture id
  // int? _textureId;
  Size? _lastSize;

  LadybirdController() {
    _lib = ffi.DynamicLibrary.process();
    _bindings = LibbirdBindings(_lib);

    _bindings.init_ladybird();
  }

  void navigate(String url) {
    final ffi.Pointer<Utf8> charPointer = url.toNativeUtf8();
    _bindings.navigate_to(charPointer.cast<ffi.Char>());
    malloc.free(charPointer);
  }

  Future<int> createTexture() async {
    return await _channel.invokeMethod('createTexture');
  }

  Future<void> unregisterTexture(int textureId) async {
    await _channel.invokeMethod('unregisterTexture', textureId);
  }

  bool resizeWindow(Size size) {
    if (size == _lastSize) return false;
    _lastSize = size;
    _bindings.resize_window(size.width.toInt(), size.height.toInt());
    return true;
  }

  int getSurfaceWidth() {
    return _bindings.get_iosurface_width();
  }

  int getSurfaceHeight() {
    return _bindings.get_iosurface_height();
  }
}

import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import 'package:flutter/services.dart';
import 'package:ladybird/src/generated/engine_bindings.g.dart';

class LadybirdController {
  final MethodChannel _channel = MethodChannel('ladybird');
  late final ffi.DynamicLibrary _lib;
  late final LadybirdBindings _bindings;
  // int? _textureId;
  Size? _lastSize;
  late final int viewId;

  late final ffi.NativeCallable<ffi.Void Function()> _resizeCallback;
  void Function()? onResize;

  LadybirdController() {
    _lib = ffi.DynamicLibrary.process();
    _bindings = LadybirdBindings(_lib);

    _bindings.init_ladybird();
    viewId = _bindings.create_web_view();

    _resizeCallback = ffi.NativeCallable<ffi.Void Function()>.listener(
      _onResize,
    );
    _bindings.set_resize_callback(viewId, _resizeCallback.nativeFunction);
  }

  void _onResize() {
    onResize?.call();
  }

  void navigate(String url) {
    final ffi.Pointer<Utf8> charPointer = url.toNativeUtf8();
    _bindings.navigate_to(viewId, charPointer.cast<ffi.Char>());
    malloc.free(charPointer);
  }

  Future<int> createTexture() async {
    return await _channel.invokeMethod('createTexture', viewId);
  }

  Future<void> unregisterTexture(int textureId) async {
    await _channel.invokeMethod('unregisterTexture', textureId);
  }

  bool resizeWindow(Size size) {
    if (size == _lastSize) return false;
    _lastSize = size;
    _bindings.resize_window(viewId, size.width.toInt(), size.height.toInt());
    return true;
  }

  int getSurfaceWidth() {
    return _bindings.get_iosurface_width(viewId);
  }

  int getSurfaceHeight() {
    return _bindings.get_iosurface_height(viewId);
  }

  void dispatchMouseEvent({
    required int type,
    required int x,
    required int y,
    required int button,
    required int buttons,
    required int modifiers,
    required int wheelDeltaX,
    required int wheelDeltaY,
  }) {
    _bindings.dispatch_mouse_event(
      viewId,
      type,
      x,
      y,
      button,
      buttons,
      modifiers,
      wheelDeltaX,
      wheelDeltaY,
    );
  }

  void dispatchKeyEvent({
    required int type,
    required int keycode,
    required int modifiers,
    required int codePoint,
    required bool repeat,
  }) {
    _bindings.dispatch_key_event(
      viewId,
      type,
      keycode,
      modifiers,
      codePoint,
      repeat,
    );
  }

  void dispose() {
    _resizeCallback.close();
    _bindings.destroy_web_view(viewId);
  }
}

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:ladybird/src/generated/engine_bindings.g.dart';
import 'dart:ui' as ui;

abstract class LadybirdEngineBindings {
  void init_ladybird();
  int create_web_view();
  void destroy_web_view(int view_id);
  void set_resize_callback(int view_id, ResizeCallback callback);
  void set_url_change_callback(int view_id, UrlChangeCallback callback);
  void set_title_change_callback(int view_id, TitleChangeCallback callback);
  void set_favicon_change_callback(int view_id, FaviconChangeCallback callback);
  void set_zoom(int view_id, double zoom);
  void navigate_to(int view_id, ffi.Pointer<ffi.Char> url);
  void reload_tab(int view_id);
  void go_back(int view_id);
  void go_forward(int view_id);
  bool can_go_back(int view_id);
  bool can_go_forward(int view_id);
  void resize_window(int view_id, int width, int height);
  int get_iosurface_width(int view_id);
  int get_iosurface_height(int view_id);
  void dispatch_mouse_event(
    int view_id,
    int type,
    int x,
    int y,
    int button,
    int buttons,
    int modifiers,
    int wheel_delta_x,
    int wheel_delta_y,
  );
  void dispatch_key_event(
    int view_id,
    int type,
    int keycode,
    int modifiers,
    int code_point,
    bool repeat,
  );
}

class FfiLadybirdEngineBindings implements LadybirdEngineBindings {
  final LadybirdBindings _bindings;

  FfiLadybirdEngineBindings(this._bindings);

  @override
  void init_ladybird() => _bindings.init_ladybird();

  @override
  int create_web_view() => _bindings.create_web_view();

  @override
  void destroy_web_view(int view_id) => _bindings.destroy_web_view(view_id);

  @override
  void set_resize_callback(int view_id, ResizeCallback callback) =>
      _bindings.set_resize_callback(view_id, callback);

  @override
  void set_url_change_callback(int view_id, UrlChangeCallback callback) =>
      _bindings.set_url_change_callback(view_id, callback);

  @override
  void set_title_change_callback(int view_id, TitleChangeCallback callback) =>
      _bindings.set_title_change_callback(view_id, callback);

  @override
  void set_favicon_change_callback(
    int view_id,
    FaviconChangeCallback callback,
  ) => _bindings.set_favicon_change_callback(view_id, callback);

  @override
  void set_zoom(int view_id, double zoom) => _bindings.set_zoom(view_id, zoom);

  @override
  void navigate_to(int view_id, ffi.Pointer<ffi.Char> url) =>
      _bindings.navigate_to(view_id, url);

  @override
  void reload_tab(int view_id) => _bindings.reload_tab(view_id);

  @override
  void go_back(int view_id) => _bindings.go_back(view_id);

  @override
  void go_forward(int view_id) => _bindings.go_forward(view_id);

  @override
  bool can_go_back(int view_id) => _bindings.can_go_back(view_id);

  @override
  bool can_go_forward(int view_id) => _bindings.can_go_forward(view_id);

  @override
  void resize_window(int view_id, int width, int height) =>
      _bindings.resize_window(view_id, width, height);

  @override
  int get_iosurface_width(int view_id) =>
      _bindings.get_iosurface_width(view_id);

  @override
  int get_iosurface_height(int view_id) =>
      _bindings.get_iosurface_height(view_id);

  @override
  void dispatch_mouse_event(
    int view_id,
    int type,
    int x,
    int y,
    int button,
    int buttons,
    int modifiers,
    int wheel_delta_x,
    int wheel_delta_y,
  ) => _bindings.dispatch_mouse_event(
    view_id,
    type,
    x,
    y,
    button,
    buttons,
    modifiers,
    wheel_delta_x,
    wheel_delta_y,
  );

  @override
  void dispatch_key_event(
    int view_id,
    int type,
    int keycode,
    int modifiers,
    int code_point,
    bool repeat,
  ) => _bindings.dispatch_key_event(
    view_id,
    type,
    keycode,
    modifiers,
    code_point,
    repeat,
  );
}

class LadybirdController {
  final MethodChannel _channel = MethodChannel('ladybird');
  ffi.DynamicLibrary? _lib;
  late final LadybirdEngineBindings _bindings;
  // int? _textureId;
  Size? _lastSize;
  late final int _viewId;
  final String initialUrl;
  bool hasNavigatedInitial = false;
  final TextEditingController textController = TextEditingController();

  late final ffi.NativeCallable<ffi.Void Function()> _resizeCallback;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>)>
  _urlChangeCallback;
  late final ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>)>
  _titleChangeCallback;
  late final ffi.NativeCallable<
    ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Int, ffi.Int)
  >
  _faviconChangeCallback;

  void Function()? onResize;

  final ValueNotifier<String> urlNotifier = ValueNotifier("");
  final ValueNotifier<String> titleNotifier = ValueNotifier("Tab");
  final ValueNotifier<dynamic> faviconNotifier = ValueNotifier(null);

  int get viewId => _viewId;

  static ffi.DynamicLibrary _openEngineLibrary() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libladybird_plugin.so');
    }
    return ffi.DynamicLibrary.process();
  }

  LadybirdController({
    this.initialUrl = "https://google.com/",
    LadybirdEngineBindings? bindings,
  }) {
    if (bindings != null) {
      _bindings = bindings;
    } else {
      _lib = _openEngineLibrary();
      _bindings = FfiLadybirdEngineBindings(LadybirdBindings(_lib!));
    }
    _bindings.init_ladybird();
    _viewId = _bindings.create_web_view();
    if (_viewId < 0) {
      throw StateError(
        'Failed to create Ladybird web view (native initialization failed).',
      );
    }
    print("view view id: $viewId");

    _resizeCallback = ffi.NativeCallable<ffi.Void Function()>.listener(
      _onResize,
    );
    _bindings.set_resize_callback(_viewId, _resizeCallback.nativeFunction);

    _urlChangeCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>)>.listener(
          _onUrlChange,
        );
    _bindings.set_url_change_callback(
      _viewId,
      _urlChangeCallback.nativeFunction,
    );

    _titleChangeCallback =
        ffi.NativeCallable<ffi.Void Function(ffi.Pointer<ffi.Char>)>.listener(
          _onTitleChange,
        );
    _bindings.set_title_change_callback(
      _viewId,
      _titleChangeCallback.nativeFunction,
    );

    _faviconChangeCallback =
        ffi.NativeCallable<
          ffi.Void Function(ffi.Pointer<ffi.Uint8>, ffi.Int, ffi.Int)
        >.listener(_onFaviconChange);
    _bindings.set_favicon_change_callback(
      _viewId,
      _faviconChangeCallback.nativeFunction,
    );

    _bindings.set_zoom(_viewId, 2);
  }

  void _onUrlChange(ffi.Pointer<ffi.Char> urlPointer) {
    if (urlPointer != ffi.nullptr) {
      final url = urlPointer.cast<Utf8>().toDartString();
      textController.text = url;
      urlNotifier.value = url;
      malloc.free(urlPointer);
    }
  }

  void _onTitleChange(ffi.Pointer<ffi.Char> titlePointer) {
    if (titlePointer != ffi.nullptr) {
      final title = titlePointer.cast<Utf8>().toDartString();
      titleNotifier.value = title;
      malloc.free(titlePointer);
    }
  }

  void _onFaviconChange(
    ffi.Pointer<ffi.Uint8> dataPointer,
    int width,
    int height,
  ) {
    if (dataPointer != ffi.nullptr) {
      if (width > 0 && height > 0) {
        final length = width * height * 4;
        final bgraBytes = dataPointer.asTypedList(length);
        final rgbaBytes = Uint8List(length);
        for (int i = 0; i < length; i += 4) {
          rgbaBytes[i] = bgraBytes[i + 2]; // R
          rgbaBytes[i + 1] = bgraBytes[i + 1]; // G
          rgbaBytes[i + 2] = bgraBytes[i]; // B
          rgbaBytes[i + 3] = bgraBytes[i + 3]; // A
        }

        ui.decodeImageFromPixels(
          rgbaBytes,
          width,
          height,
          ui.PixelFormat.rgba8888,
          (image) {
            faviconNotifier.value = image;
          },
        );
      }
      malloc.free(dataPointer);
    }
  }

  void _onResize() {
    onResize?.call();
  }

  void navigate(String url) {
    String parsedUrl = url;
    // todo: more reliable system for other formats, such as file://
    if (!url.startsWith("http")) {
      parsedUrl = "https://$url";
    }
    textController.text = parsedUrl;
    final ffi.Pointer<Utf8> charPointer = parsedUrl.toNativeUtf8();
    _bindings.navigate_to(_viewId, charPointer.cast<ffi.Char>());
    _bindings.set_zoom(_viewId, 2);
    malloc.free(charPointer);
  }

  void reload() {
    _bindings.reload_tab(_viewId);
  }

  void goBack() {
    _bindings.go_back(_viewId);
  }

  void goForward() {
    _bindings.go_forward(_viewId);
  }

  bool canGoBack() {
    return _bindings.can_go_back(_viewId);
  }

  bool canGoForward() {
    return _bindings.can_go_forward(_viewId);
  }

  Future<int> createTexture() async {
    try {
      return await _channel.invokeMethod('createTexture', _viewId);
    } on MissingPluginException {
      return -1;
    }
  }

  Future<void> unregisterTexture(int textureId) async {
    if (textureId < 0) return;
    try {
      await _channel.invokeMethod('unregisterTexture', textureId);
    } on MissingPluginException {
      // No platform texture channel is available in this build.
    }
  }

  bool resizeWindow(Size size) {
    if (size == _lastSize) return false;
    _lastSize = size;
    _bindings.resize_window(_viewId, size.width.toInt(), size.height.toInt());
    return true;
  }

  int getSurfaceWidth() {
    return _bindings.get_iosurface_width(_viewId);
  }

  int getSurfaceHeight() {
    return _bindings.get_iosurface_height(_viewId);
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
      _viewId,
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
      _viewId,
      type,
      keycode,
      modifiers,
      codePoint,
      repeat,
    );
  }

  void dispose() {
    _resizeCallback.close();
    _urlChangeCallback.close();
    _titleChangeCallback.close();
    _faviconChangeCallback.close();
    _bindings.destroy_web_view(_viewId);
  }
}

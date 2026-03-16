import 'dart:ffi' as ffi;

import 'package:flutter_test/flutter_test.dart';
import 'package:ladybird/src/controller.dart';
import 'package:ladybird/src/generated/engine_bindings.g.dart';

class _FakeBindings implements LadybirdEngineBindings {
  _FakeBindings({required this.createWebViewResult});

  final int createWebViewResult;
  bool initialized = false;
  int? destroyedViewId;

  @override
  void init_ladybird() {
    initialized = true;
  }

  @override
  int create_web_view() => createWebViewResult;

  @override
  void destroy_web_view(int view_id) {
    destroyedViewId = view_id;
  }

  @override
  bool can_go_back(int view_id) => false;

  @override
  bool can_go_forward(int view_id) => false;

  @override
  void dispatch_key_event(
    int view_id,
    int type,
    int keycode,
    int modifiers,
    int code_point,
    bool repeat,
  ) {}

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
  ) {}

  @override
  int get_iosurface_height(int view_id) => 0;

  @override
  int get_iosurface_width(int view_id) => 0;

  @override
  void go_back(int view_id) {}

  @override
  void go_forward(int view_id) {}

  @override
  void navigate_to(int view_id, ffi.Pointer<ffi.Char> url) {}

  @override
  void reload_tab(int view_id) {}

  @override
  void resize_window(int view_id, int width, int height) {}

  @override
  void set_favicon_change_callback(
    int view_id,
    FaviconChangeCallback callback,
  ) {}

  @override
  void set_resize_callback(int view_id, ResizeCallback callback) {}

  @override
  void set_title_change_callback(int view_id, TitleChangeCallback callback) {}

  @override
  void set_url_change_callback(int view_id, UrlChangeCallback callback) {}

  @override
  void set_zoom(int view_id, double zoom) {}
}

void main() {
  test('throws a StateError when native webview creation fails', () {
    final bindings = _FakeBindings(createWebViewResult: -1);

    expect(
      () => LadybirdController(bindings: bindings),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Failed to create Ladybird web view'),
        ),
      ),
    );

    expect(bindings.initialized, isTrue);
  });

  test('creates and disposes a webview when native creation succeeds', () {
    final bindings = _FakeBindings(createWebViewResult: 42);

    final controller = LadybirdController(bindings: bindings);

    expect(controller.viewId, 42);

    controller.dispose();
    expect(bindings.destroyedViewId, 42);
  });
}

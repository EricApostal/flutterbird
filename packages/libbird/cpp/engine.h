#ifndef ENGINE_H
#define ENGINE_H

#include <stdbool.h>
#include <stdint.h>

#if defined(_WIN32)
    #define LADYBIRD_API __declspec(dllexport)
#else
    #define LADYBIRD_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*FrameCallback)(void*);
typedef void (*ResizeCallback)();

LADYBIRD_API void init_ladybird();

LADYBIRD_API void* get_latest_pixel_buffer();

LADYBIRD_API void set_frame_callback(FrameCallback callback, void* context);

LADYBIRD_API void set_resize_callback(ResizeCallback callback);

LADYBIRD_API void resize_window(int width, int height);

LADYBIRD_API void navigate_to(const char* url);

LADYBIRD_API void set_zoom(double zoom);

LADYBIRD_API int get_iosurface_width();

LADYBIRD_API int get_iosurface_height();

LADYBIRD_API void dispatch_mouse_event(int type, int x, int y, int button, int buttons, int modifiers, int wheel_delta_x, int wheel_delta_y);

LADYBIRD_API void dispatch_key_event(int type, int keycode, int modifiers, uint32_t code_point, bool repeat);

#ifdef __cplusplus
}
#endif

#endif // ENGINE_H
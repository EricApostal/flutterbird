#ifndef ENGINE_H
#define ENGINE_H

#if defined(_WIN32)
    #define LADYBIRD_API __declspec(dllexport)
#else
    #define LADYBIRD_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*FrameCallback)(void*);

LADYBIRD_API void init_ladybird();

LADYBIRD_API void* get_latest_pixel_buffer();

LADYBIRD_API void set_frame_callback(FrameCallback callback, void* context);

LADYBIRD_API void resize_window(int width, int height);

LADYBIRD_API void navigate_to(const char* url);

LADYBIRD_API void set_zoom(double zoom);

#ifdef __cplusplus
}
#endif

#endif // ENGINE_H
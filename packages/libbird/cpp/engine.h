#ifndef ENGINE_H
#define ENGINE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*FrameCallback)(void*);

__attribute__((visibility("default"))) __attribute__((used))
void init_ladybird();

__attribute__((visibility("default"))) __attribute__((used))
void* get_latest_pixel_buffer();

__attribute__((visibility("default"))) __attribute__((used))
void set_frame_callback(FrameCallback callback, void* context);

__attribute__((visibility("default"))) __attribute__((used))
void resize_ladybird(int width, int height);

#ifdef __cplusplus
}
#endif

#endif // ENGINE_H

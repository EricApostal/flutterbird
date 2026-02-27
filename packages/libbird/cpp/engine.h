#ifndef ENGINE_H
#define ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

__attribute__((visibility("default"))) __attribute__((used))
void init_ladybird();

__attribute__((visibility("default"))) __attribute__((used))
uint8_t* get_latest_frame(int* out_width, int* out_height);

__attribute__((visibility("default"))) __attribute__((used))
void free_frame(uint8_t* buffer);

#ifdef __cplusplus
}
#endif

#endif // ENGINE_H

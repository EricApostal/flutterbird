#include <stdint.h>
#include <stdlib.h>
// clang++ -shared -fPIC -o libengine.dylib engine.cpp
extern "C" {
    __attribute__((visibility("default"))) __attribute__((used))
    uint8_t* generate_frame(int width, int height) {
        int size = width * height * 4;
        uint8_t* buffer = (uint8_t*)malloc(size);
        
        for (int i = 0; i < size; i += 4) {
            buffer[i] = 255;     
            buffer[i+1] = 0;     
            buffer[i+2] = 0;     
            buffer[i+3] = 255;   
        }
        
        return buffer;
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void free_frame(uint8_t* buffer) {
        free(buffer);
    }
}
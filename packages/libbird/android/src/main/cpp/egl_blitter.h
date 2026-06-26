#pragma once

#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/hardware_buffer.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>

class EglBlitter {
public:
    EglBlitter();
    ~EglBlitter();

    bool init(ANativeWindow* window);
    void destroy();
    void draw(AHardwareBuffer* ahb, int width, int height);

private:
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    ANativeWindow* m_window = nullptr;

    GLuint program = 0;
    GLuint aPosition = 0;
    GLuint aTexCoord = 0;
    GLuint uTexture = 0;

    PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC eglGetNativeClientBufferANDROID = nullptr;
    PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR = nullptr;
    PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR = nullptr;
    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC glEGLImageTargetTexture2DOES = nullptr;
};

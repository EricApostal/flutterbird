#include "egl_blitter.h"
#include <android/log.h>
#include <string.h>

#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "LadybirdEGL", __VA_ARGS__)

static const char* VERTEX_SHADER = R"(
attribute vec4 aPosition;
attribute vec2 aTexCoord;
varying vec2 vTexCoord;
void main() {
    gl_Position = aPosition;
    vTexCoord = aTexCoord;
}
)";

static const char* FRAGMENT_SHADER = R"(
#extension GL_OES_EGL_image_external : require
precision mediump float;
varying vec2 vTexCoord;
uniform samplerExternalOES uTexture;
void main() {
    gl_FragColor = texture2D(uTexture, vTexCoord);
}
)";

static GLuint loadShader(GLenum type, const char* source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        LOGE("Could not compile shader");
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static GLuint createProgram(const char* vertexSource, const char* fragmentSource) {
    GLuint vertexShader = loadShader(GL_VERTEX_SHADER, vertexSource);
    GLuint pixelShader = loadShader(GL_FRAGMENT_SHADER, fragmentSource);
    GLuint program = glCreateProgram();
    glAttachShader(program, vertexShader);
    glAttachShader(program, pixelShader);
    glLinkProgram(program);
    GLint linkStatus = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &linkStatus);
    if (linkStatus != GL_TRUE) {
        LOGE("Could not link program");
        glDeleteProgram(program);
        return 0;
    }
    return program;
}

EglBlitter::EglBlitter() {}

EglBlitter::~EglBlitter() {
    destroy();
}

bool EglBlitter::init(ANativeWindow* window) {
    if (display != EGL_NO_DISPLAY) {
        destroy();
    }

    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
        LOGE("eglGetDisplay failed");
        return false;
    }

    EGLint major, minor;
    if (!eglInitialize(display, &major, &minor)) {
        LOGE("eglInitialize failed");
        return false;
    }

    const EGLint configAttribs[] = {
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_BLUE_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_RED_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };

    EGLConfig config;
    EGLint numConfigs;
    if (!eglChooseConfig(display, configAttribs, &config, 1, &numConfigs) || numConfigs == 0) {
        LOGE("eglChooseConfig failed");
        return false;
    }

    const EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
    if (context == EGL_NO_CONTEXT) {
        LOGE("eglCreateContext failed");
        return false;
    }

    surface = eglCreateWindowSurface(display, config, window, nullptr);
    if (surface == EGL_NO_SURFACE) {
        LOGE("eglCreateWindowSurface failed");
        return false;
    }

    if (!eglMakeCurrent(display, surface, surface, context)) {
        LOGE("eglMakeCurrent failed");
        return false;
    }

    program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER);
    if (!program) {
        LOGE("createProgram failed");
        return false;
    }

    aPosition = glGetAttribLocation(program, "aPosition");
    aTexCoord = glGetAttribLocation(program, "aTexCoord");
    uTexture = glGetUniformLocation(program, "uTexture");

    eglGetNativeClientBufferANDROID = (PFNEGLGETNATIVECLIENTBUFFERANDROIDPROC)eglGetProcAddress("eglGetNativeClientBufferANDROID");
    eglCreateImageKHR = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
    eglDestroyImageKHR = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    glEGLImageTargetTexture2DOES = (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress("glEGLImageTargetTexture2DOES");

    m_window = window;
    ANativeWindow_acquire(m_window);

    // Release context from current thread so the render thread can acquire it
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglSwapInterval(display, 0);

    return true;
}

void EglBlitter::destroy() {
    if (display != EGL_NO_DISPLAY) {
        eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (surface != EGL_NO_SURFACE) {
            eglDestroySurface(display, surface);
            surface = EGL_NO_SURFACE;
        }
        if (context != EGL_NO_CONTEXT) {
            eglDestroyContext(display, context);
            context = EGL_NO_CONTEXT;
        }
        if (program != 0) {
            glDeleteProgram(program);
            program = 0;
        }
        eglTerminate(display);
        display = EGL_NO_DISPLAY;
    }
    if (m_window) {
        ANativeWindow_release(m_window);
        m_window = nullptr;
    }
}

void EglBlitter::draw(AHardwareBuffer* ahb, int width, int height) {
    if (display == EGL_NO_DISPLAY || !ahb || !eglCreateImageKHR || !glEGLImageTargetTexture2DOES) {
        return;
    }

    if (!eglMakeCurrent(display, surface, surface, context)) {
        LOGE("eglMakeCurrent failed in draw: %x", eglGetError());
        return;
    }

    EGLClientBuffer clientBuffer = nullptr;
    if (eglGetNativeClientBufferANDROID) {
        clientBuffer = eglGetNativeClientBufferANDROID(ahb);
    } else {
        // Fallback for some systems where ahb can be cast directly
        clientBuffer = (EGLClientBuffer)ahb;
    }

    EGLint eglImageAttributes[] = {EGL_NONE};
    EGLImageKHR image = eglCreateImageKHR(display, EGL_NO_CONTEXT, EGL_NATIVE_BUFFER_ANDROID, clientBuffer, eglImageAttributes);
    if (image == EGL_NO_IMAGE_KHR) {
        LOGE("eglCreateImageKHR failed");
        return;
    }

    GLuint texture;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_EXTERNAL_OES, texture);
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES, (GLeglImageOES)image);

    int window_height = ANativeWindow_getHeight(m_window);
    glViewport(0, window_height - height, width, height);
    glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(program);

    // Render full screen quad (vertically flipped because hardware buffer origin might differ, wait, Ladybird might already handle it. We will draw normally).
    // Let's do standard orientation. 
    GLfloat vertices[] = {
        -1.0f, -1.0f, 0.0f,
         1.0f, -1.0f, 0.0f,
        -1.0f,  1.0f, 0.0f,
         1.0f,  1.0f, 0.0f,
    };
    GLfloat texCoords[] = {
        0.0f, 1.0f,
        1.0f, 1.0f,
        0.0f, 0.0f,
        1.0f, 0.0f,
    };

    glVertexAttribPointer(aPosition, 3, GL_FLOAT, GL_FALSE, 0, vertices);
    glEnableVertexAttribArray(aPosition);
    glVertexAttribPointer(aTexCoord, 2, GL_FLOAT, GL_FALSE, 0, texCoords);
    glEnableVertexAttribArray(aTexCoord);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_EXTERNAL_OES, texture);
    glUniform1i(uTexture, 0);

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    if (!eglSwapBuffers(display, surface)) {
        LOGE("eglSwapBuffers failed: %x", eglGetError());
    }

    glBindTexture(GL_TEXTURE_EXTERNAL_OES, 0);
    glDeleteTextures(1, &texture);
    eglDestroyImageKHR(display, image);
}

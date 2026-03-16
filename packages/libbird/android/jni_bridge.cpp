#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>

using InitLadybirdFn = void (*)();
using TickLadybirdFn = void (*)();
using RegisterAndroidPluginFn = void (*)(JNIEnv*, jobject);
using GetLatestPixelBufferFn = void* (*)(int);
using GetPixelBufferSizeFn = int (*)(int);
using GetTextureDimensionFn = int (*)(int);

static void* s_engine_handle = nullptr;
static InitLadybirdFn s_init_ladybird = nullptr;
static TickLadybirdFn s_tick_ladybird = nullptr;
static RegisterAndroidPluginFn s_register_android_plugin = nullptr;
static GetLatestPixelBufferFn s_get_latest_pixel_buffer = nullptr;
static GetPixelBufferSizeFn s_get_pixel_buffer_size = nullptr;
static GetTextureDimensionFn s_get_iosurface_width = nullptr;
static GetTextureDimensionFn s_get_iosurface_height = nullptr;

static bool ensure_engine_symbols_loaded()
{
    if (s_engine_handle)
        return s_init_ladybird && s_tick_ladybird && s_register_android_plugin && s_get_latest_pixel_buffer && s_get_pixel_buffer_size && s_get_iosurface_width && s_get_iosurface_height;

    s_engine_handle = dlopen("libladybird_plugin.so", RTLD_NOW | RTLD_GLOBAL);
    if (!s_engine_handle) {
        __android_log_print(ANDROID_LOG_ERROR, "LadybirdJNI", "dlopen(libladybird_plugin.so) failed: %s", dlerror());
        return false;
    }

    s_init_ladybird = reinterpret_cast<InitLadybirdFn>(dlsym(s_engine_handle, "init_ladybird"));
    s_tick_ladybird = reinterpret_cast<TickLadybirdFn>(dlsym(s_engine_handle, "tick_ladybird"));
    s_register_android_plugin = reinterpret_cast<RegisterAndroidPluginFn>(dlsym(s_engine_handle, "register_android_plugin_instance"));
    s_get_latest_pixel_buffer = reinterpret_cast<GetLatestPixelBufferFn>(dlsym(s_engine_handle, "get_latest_pixel_buffer"));
    s_get_pixel_buffer_size = reinterpret_cast<GetPixelBufferSizeFn>(dlsym(s_engine_handle, "get_pixel_buffer_size"));
    s_get_iosurface_width = reinterpret_cast<GetTextureDimensionFn>(dlsym(s_engine_handle, "get_iosurface_width"));
    s_get_iosurface_height = reinterpret_cast<GetTextureDimensionFn>(dlsym(s_engine_handle, "get_iosurface_height"));

    if (!s_init_ladybird || !s_tick_ladybird || !s_register_android_plugin || !s_get_latest_pixel_buffer || !s_get_pixel_buffer_size || !s_get_iosurface_width || !s_get_iosurface_height) {
        __android_log_print(ANDROID_LOG_ERROR, "LadybirdJNI", "dlsym failed for one or more symbols");
        return false;
    }

    return true;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_ladybird_LadybirdPlugin_nativeInitLadybird(JNIEnv* env, jobject thiz)
{
    if (ensure_engine_symbols_loaded()) {
        s_register_android_plugin(env, thiz);
        s_init_ladybird();
    } else {
        __android_log_print(ANDROID_LOG_ERROR, "LadybirdJNI", "nativeInitLadybird failed to load symbols");
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_ladybird_LadybirdPlugin_nativeTickLadybird(JNIEnv* env, jobject thiz)
{
    (void)env;
    (void)thiz;
    if (ensure_engine_symbols_loaded()) {
        s_tick_ladybird();
    } else {
        __android_log_print(ANDROID_LOG_ERROR, "LadybirdJNI", "nativeTickLadybird failed to load symbols");
    }
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_example_ladybird_LadybirdPlugin_nativeGetLatestPixelBuffer(JNIEnv* env, jobject, jint view_id)
{
    if (!ensure_engine_symbols_loaded())
        return nullptr;

    void* pixels = s_get_latest_pixel_buffer(view_id);
    if (!pixels)
        return nullptr;

    int buffer_size = s_get_pixel_buffer_size(view_id);
    if (buffer_size <= 0)
        return nullptr;

    return env->NewDirectByteBuffer(pixels, static_cast<jlong>(buffer_size));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_ladybird_LadybirdPlugin_nativeGetTextureWidth(JNIEnv*, jobject, jint view_id)
{
    if (!ensure_engine_symbols_loaded())
        return 0;
    return s_get_iosurface_width(view_id);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_ladybird_LadybirdPlugin_nativeGetTextureHeight(JNIEnv*, jobject, jint view_id)
{
    if (!ensure_engine_symbols_loaded())
        return 0;
    return s_get_iosurface_height(view_id);
}

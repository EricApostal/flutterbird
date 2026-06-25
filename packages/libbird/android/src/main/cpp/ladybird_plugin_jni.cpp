#include "../../../../cpp/engine.h"

#include <android/hardware_buffer_jni.h>
#include <jni.h>

#include <algorithm>

static const char *get_utf_chars(JNIEnv *env, jstring value) {
  if (!value)
    return nullptr;
  return env->GetStringUTFChars(value, nullptr);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_flutterbird_ladybird_LadybirdPlugin_nativeConfigureAndroid(
    JNIEnv *env, jclass, jstring resource_root, jstring user_dir,
    jstring native_library_dir, jstring certificates_path) {
  auto const *resource_root_chars = get_utf_chars(env, resource_root);
  auto const *user_dir_chars = get_utf_chars(env, user_dir);
  auto const *native_library_dir_chars = get_utf_chars(env, native_library_dir);
  auto const *certificates_path_chars = get_utf_chars(env, certificates_path);

  configure_android_runtime(resource_root_chars, user_dir_chars,
                            native_library_dir_chars, certificates_path_chars);

  if (resource_root_chars)
    env->ReleaseStringUTFChars(resource_root, resource_root_chars);
  if (user_dir_chars)
    env->ReleaseStringUTFChars(user_dir, user_dir_chars);
  if (native_library_dir_chars)
    env->ReleaseStringUTFChars(native_library_dir, native_library_dir_chars);
  if (certificates_path_chars)
    env->ReleaseStringUTFChars(certificates_path, certificates_path_chars);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_flutterbird_ladybird_LadybirdPlugin_nativeTickLadybird(JNIEnv *,
                                                                jclass) {
  tick_ladybird();
}

extern "C" JNIEXPORT jlong JNICALL
Java_dev_flutterbird_ladybird_LadybirdPlugin_nativeGetFrameGeneration(
    JNIEnv *, jclass, jint view_id) {
  return static_cast<jlong>(get_frame_generation(view_id));
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_flutterbird_ladybird_LadybirdPlugin_nativeGetSurfaceWidth(
    JNIEnv *, jclass, jint view_id) {
  return get_iosurface_width(view_id);
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_flutterbird_ladybird_LadybirdPlugin_nativeGetSurfaceHeight(
    JNIEnv *, jclass, jint view_id) {
  return get_iosurface_height(view_id);
}

extern "C" JNIEXPORT jobject JNICALL
Java_dev_flutterbird_ladybird_LadybirdPlugin_nativeGetHardwareBuffer(
    JNIEnv *env, jclass, jint view_id) {
  void *ahb = get_android_hardware_buffer(view_id);
  if (!ahb)
    return nullptr;

#if __ANDROID_API__ >= 26
  return AHardwareBuffer_toHardwareBuffer(
      env, static_cast<AHardwareBuffer *>(ahb));
#else
  return nullptr;
#endif
}
#include "../../../../cpp/engine.h"

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

extern "C" JNIEXPORT jboolean JNICALL
Java_dev_flutterbird_ladybird_LadybirdPlugin_nativeCopyLatestPixelBuffer(
    JNIEnv *env, jclass, jint view_id, jobject pixel_buffer, jint capacity) {
  if (!pixel_buffer || capacity <= 0)
    return JNI_FALSE;

  auto *buffer =
      static_cast<uint8_t *>(env->GetDirectBufferAddress(pixel_buffer));
  auto buffer_capacity = env->GetDirectBufferCapacity(pixel_buffer);
  if (!buffer || buffer_capacity <= 0)
    return JNI_FALSE;

  int width = 0;
  int height = 0;
  auto effective_capacity = static_cast<int>(
      std::min<jlong>(buffer_capacity, static_cast<jlong>(capacity)));
  bool copied = copy_latest_pixel_buffer(view_id, buffer, effective_capacity,
                                         &width, &height);
  if (!copied)
    return JNI_FALSE;

  if (width > 0 && height > 0) {
    auto const pixel_count =
        static_cast<size_t>(width) * static_cast<size_t>(height);
    auto const required_bytes = pixel_count * 4;
    if (required_bytes <= static_cast<size_t>(effective_capacity)) {
      for (size_t i = 0; i < pixel_count; ++i) {
        auto offset = i * 4;
        std::swap(buffer[offset], buffer[offset + 2]);
      }
    }
  }

  return JNI_TRUE;
}
#include "include/ladybird/ladybird_plugin.h"

#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>

#include "engine.h"
#include "ladybird_plugin_private.h"

struct _LadybirdTexture {
  FlTextureGL parent_instance;
  int view_id;
  FlTextureRegistrar *texture_registrar;

  // CPU fallback path state.
  uint8_t *packed_frame_buffer;
  size_t packed_frame_capacity;

  // Shared GL texture object used by both dma-buf and CPU upload paths.
  uint32_t texture_name;
  int texture_width;
  int texture_height;

  // Zero-copy dma-buf import state.
  EGLDisplay egl_display;
  EGLImageKHR egl_image;
  int egl_image_fd;
  int egl_image_width;
  int egl_image_height;
  int egl_image_pitch;
  uint32_t egl_image_drm_format;
  uint64_t egl_image_modifier;
  bool egl_image_premultiplied;
  bool dmabuf_import_disabled;

  uint64_t last_frame_generation;
};

G_DECLARE_FINAL_TYPE(LadybirdTexture, ladybird_texture, LADYBIRD, TEXTURE,
                     FlTextureGL)

G_DEFINE_TYPE(LadybirdTexture, ladybird_texture, fl_texture_gl_get_type())

static void ensure_gl_texture(LadybirdTexture *self);

static void release_dmabuf_image(LadybirdTexture *self) {
  if (self->egl_image != EGL_NO_IMAGE_KHR &&
      self->egl_display != EGL_NO_DISPLAY) {
    eglDestroyImageKHR(self->egl_display, self->egl_image);
    self->egl_image = EGL_NO_IMAGE_KHR;
  }
  if (self->egl_image_fd >= 0) {
    ::close(self->egl_image_fd);
    self->egl_image_fd = -1;
  }
  self->egl_image_width = 0;
  self->egl_image_height = 0;
  self->egl_image_pitch = 0;
  self->egl_image_drm_format = 0;
  self->egl_image_modifier = 0;
  self->egl_image_premultiplied = true;
}

static bool same_dmabuf_object(int fd_a, int fd_b) {
  if (fd_a < 0 || fd_b < 0)
    return false;

  struct stat a = {};
  struct stat b = {};
  if (::fstat(fd_a, &a) != 0 || ::fstat(fd_b, &b) != 0)
    return false;

  return a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}

static bool can_import_dmabuf(EGLDisplay display) {
  if (display == EGL_NO_DISPLAY)
    return false;
  if (!epoxy_has_egl_extension(display, "EGL_EXT_image_dma_buf_import"))
    return false;
  if (!epoxy_has_gl_extension("GL_OES_EGL_image"))
    return false;
  return true;
}

static bool try_populate_dmabuf(LadybirdTexture *self, uint32_t *target,
                                uint32_t *name, uint32_t *width,
                                uint32_t *height) {
  if (self->dmabuf_import_disabled)
    return false;

  LadybirdLinuxDmaBufFrame frame = {};
  if (!acquire_latest_linux_dmabuf_frame(self->view_id, &frame) ||
      frame.fd < 0 || frame.width <= 0 || frame.height <= 0 || frame.pitch <= 0)
    return false;

  EGLDisplay display = eglGetCurrentDisplay();
  if (!can_import_dmabuf(display)) {
    ::close(frame.fd);
    self->dmabuf_import_disabled = true;
    return false;
  }

  bool needs_recreate = self->egl_image == EGL_NO_IMAGE_KHR ||
                        self->egl_display != display ||
                        self->egl_image_width != frame.width ||
                        self->egl_image_height != frame.height ||
                        self->egl_image_pitch != frame.pitch ||
                        self->egl_image_drm_format != frame.drm_format ||
                        self->egl_image_modifier != frame.modifier ||
                        self->egl_image_premultiplied != frame.premultiplied ||
                        !same_dmabuf_object(frame.fd, self->egl_image_fd);

  if (needs_recreate) {
    bool has_modifiers = epoxy_has_egl_extension(
        display, "EGL_EXT_image_dma_buf_import_modifiers");

    EGLint attribs_without_modifiers[] = {
        EGL_WIDTH,
        frame.width,
        EGL_HEIGHT,
        frame.height,
        EGL_LINUX_DRM_FOURCC_EXT,
        static_cast<EGLint>(frame.drm_format),
        EGL_DMA_BUF_PLANE0_FD_EXT,
        frame.fd,
        EGL_DMA_BUF_PLANE0_OFFSET_EXT,
        0,
        EGL_DMA_BUF_PLANE0_PITCH_EXT,
        frame.pitch,
        EGL_NONE,
    };

    EGLint attribs_with_modifiers[] = {
        EGL_WIDTH,
        frame.width,
        EGL_HEIGHT,
        frame.height,
        EGL_LINUX_DRM_FOURCC_EXT,
        static_cast<EGLint>(frame.drm_format),
        EGL_DMA_BUF_PLANE0_FD_EXT,
        frame.fd,
        EGL_DMA_BUF_PLANE0_OFFSET_EXT,
        0,
        EGL_DMA_BUF_PLANE0_PITCH_EXT,
        frame.pitch,
        EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
        static_cast<EGLint>(frame.modifier & 0xffffffffu),
        EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
        static_cast<EGLint>((frame.modifier >> 32u) & 0xffffffffu),
        EGL_NONE,
    };

    EGLImageKHR image = eglCreateImageKHR(
        display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, nullptr,
        has_modifiers ? attribs_with_modifiers : attribs_without_modifiers);
    if (image == EGL_NO_IMAGE_KHR) {
      ::close(frame.fd);
      return false;
    }

    release_dmabuf_image(self);
    self->egl_display = display;
    self->egl_image = image;
    self->egl_image_fd = frame.fd;
    self->egl_image_width = frame.width;
    self->egl_image_height = frame.height;
    self->egl_image_pitch = frame.pitch;
    self->egl_image_drm_format = frame.drm_format;
    self->egl_image_modifier = frame.modifier;
    self->egl_image_premultiplied = frame.premultiplied;
  } else {
    ::close(frame.fd);
  }

  ensure_gl_texture(self);
  glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, self->egl_image);

  self->texture_width = self->egl_image_width;
  self->texture_height = self->egl_image_height;
  *target = GL_TEXTURE_2D;
  *name = self->texture_name;
  *width = static_cast<uint32_t>(self->egl_image_width);
  *height = static_cast<uint32_t>(self->egl_image_height);
  return true;
}

static void ensure_gl_texture(LadybirdTexture *self) {
  if (self->texture_name == 0) {
    glGenTextures(1, &self->texture_name);
    glBindTexture(GL_TEXTURE_2D, self->texture_name);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  } else {
    glBindTexture(GL_TEXTURE_2D, self->texture_name);
  }
}

static gboolean ladybird_texture_populate(FlTextureGL *texture,
                                          uint32_t *target, uint32_t *name,
                                          uint32_t *width, uint32_t *height,
                                          GError **error) {
  (void)error;
  LadybirdTexture *self = LADYBIRD_TEXTURE(texture);

  int w = 0;
  int h = 0;
  int pitch = 0;
  uint64_t generation = 0;
  const uint8_t *pixels = nullptr;
  void *frame_handle = nullptr;
  (void)generation;

  if (try_populate_dmabuf(self, target, name, width, height))
    return TRUE;

  ensure_gl_texture(self);
  release_dmabuf_image(self);

  auto publish_black = [&]() {
    static uint8_t kBlackPixel[] = {0, 0, 0, 255};
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    if (self->texture_width != 1 || self->texture_height != 1) {
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, kBlackPixel);
      self->texture_width = 1;
      self->texture_height = 1;
    } else {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE,
                      kBlackPixel);
    }

    *target = GL_TEXTURE_2D;
    *name = self->texture_name;
    *width = 1;
    *height = 1;
  };

  if (!acquire_latest_frame(self->view_id, &pixels, &w, &h, &pitch, &generation,
                            &frame_handle) ||
      !pixels || w <= 0 || h <= 0 || pitch <= 0) {
    publish_black();
    return TRUE;
  }

  const uint8_t *upload_pixels = pixels;
  auto tight_row_bytes = static_cast<size_t>(w) * 4;

  // If source pitch is larger than width*4, repack rows into a contiguous
  // buffer before upload.
  if (pitch != static_cast<int>(tight_row_bytes)) {
    if (pitch < static_cast<int>(tight_row_bytes)) {
      release_latest_frame(frame_handle);
      publish_black();
      return TRUE;
    }

    auto required = tight_row_bytes * static_cast<size_t>(h);
    if (self->packed_frame_capacity < required) {
      auto *new_buffer = static_cast<uint8_t *>(
          g_realloc(self->packed_frame_buffer, required));
      if (!new_buffer) {
        release_latest_frame(frame_handle);
        publish_black();
        return TRUE;
      }
      self->packed_frame_buffer = new_buffer;
      self->packed_frame_capacity = required;
    }

    for (int row = 0; row < h; ++row) {
      std::memcpy(self->packed_frame_buffer +
                      (static_cast<size_t>(row) * tight_row_bytes),
                  pixels +
                      (static_cast<size_t>(row) * static_cast<size_t>(pitch)),
                  tight_row_bytes);
    }

    upload_pixels = self->packed_frame_buffer;
  }

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  if (self->texture_width != w || self->texture_height != h) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_BGRA, GL_UNSIGNED_BYTE,
                 upload_pixels);
    self->texture_width = w;
    self->texture_height = h;
  } else {
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, GL_BGRA, GL_UNSIGNED_BYTE,
                    upload_pixels);
  }

  release_latest_frame(frame_handle);

  *target = GL_TEXTURE_2D;
  *name = self->texture_name;
  *width = static_cast<uint32_t>(w);
  *height = static_cast<uint32_t>(h);
  return TRUE;
}

static void ladybird_texture_dispose(GObject *object) {
  LadybirdTexture *self = LADYBIRD_TEXTURE(object);
  release_dmabuf_image(self);
  if (self->packed_frame_buffer) {
    g_free(self->packed_frame_buffer);
    self->packed_frame_buffer = nullptr;
    self->packed_frame_capacity = 0;
  }
  G_OBJECT_CLASS(ladybird_texture_parent_class)->dispose(object);
}

static void ladybird_texture_class_init(LadybirdTextureClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = ladybird_texture_dispose;
  FL_TEXTURE_GL_CLASS(klass)->populate = ladybird_texture_populate;
}

static void ladybird_texture_init(LadybirdTexture *self) {
  self->view_id = -1;
  self->texture_registrar = nullptr;
  self->packed_frame_buffer = nullptr;
  self->packed_frame_capacity = 0;
  self->texture_name = 0;
  self->texture_width = 0;
  self->texture_height = 0;
  self->egl_display = EGL_NO_DISPLAY;
  self->egl_image = EGL_NO_IMAGE_KHR;
  self->egl_image_fd = -1;
  self->egl_image_width = 0;
  self->egl_image_height = 0;
  self->egl_image_pitch = 0;
  self->egl_image_drm_format = 0;
  self->egl_image_modifier = 0;
  self->egl_image_premultiplied = true;
  self->dmabuf_import_disabled = false;
  self->last_frame_generation = 0;
}

static LadybirdTexture *ladybird_texture_new(int view_id,
                                             FlTextureRegistrar *registrar) {
  LadybirdTexture *self =
      LADYBIRD_TEXTURE(g_object_new(ladybird_texture_get_type(), nullptr));
  self->view_id = view_id;
  self->texture_registrar = registrar;
  return self;
}

#define LADYBIRD_PLUGIN(obj)                                                   \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), ladybird_plugin_get_type(),               \
                              LadybirdPlugin))

struct _LadybirdPlugin {
  GObject parent_instance;
  FlPluginRegistrar *registrar;
  FlTextureRegistrar *texture_registrar;
  std::map<int64_t, LadybirdTexture *> *textures;
};

G_DEFINE_TYPE(LadybirdPlugin, ladybird_plugin, g_object_get_type())

static bool g_ladybird_initialized = false;
static constexpr guint kLadybirdTickIntervalMs = 8;

static gboolean ladybird_tick_callback(gpointer user_data) {
  LadybirdPlugin *plugin = LADYBIRD_PLUGIN(user_data);
  tick_ladybird();

  if (plugin && plugin->textures) {
    for (auto const &it : *plugin->textures) {
      LadybirdTexture *texture = it.second;
      if (texture && texture->texture_registrar) {
        uint64_t generation = get_frame_generation(texture->view_id);
        if (generation != 0 && generation != texture->last_frame_generation) {
          texture->last_frame_generation = generation;
          fl_texture_registrar_mark_texture_frame_available(
              texture->texture_registrar, FL_TEXTURE(texture));
        }
      }
    }
  }

  return G_SOURCE_CONTINUE;
}

static void ladybird_plugin_handle_method_call(LadybirdPlugin *self,
                                               FlMethodCall *method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar *method = fl_method_call_get_name(method_call);

  if (!g_ladybird_initialized) {
    init_ladybird();
    g_ladybird_initialized = true;
    g_timeout_add(kLadybirdTickIntervalMs, ladybird_tick_callback, self);
  }

  if (strcmp(method, "getPlatformVersion") == 0) {
    struct utsname uname_data = {};
    uname(&uname_data);
    g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
    g_autoptr(FlValue) result = fl_value_new_string(version);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "createTexture") == 0) {
    FlValue *args = fl_method_call_get_args(method_call);

    if (fl_value_get_type(args) == FL_VALUE_TYPE_INT) {
      int64_t view_id = fl_value_get_int(args);

      LadybirdTexture *texture =
          ladybird_texture_new((int)view_id, self->texture_registrar);
      fl_texture_registrar_register_texture(self->texture_registrar,
                                            FL_TEXTURE(texture));

      // GTK timer + frame generation drive texture notifications.
      set_frame_callback((int)view_id, nullptr, nullptr);

      int64_t texture_id = (int64_t)fl_texture_get_id(FL_TEXTURE(texture));

      if (self->textures) {
        self->textures->insert(std::make_pair(texture_id, texture));
      }

      g_autoptr(FlValue) result = fl_value_new_int(texture_id);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "Expected int viewId", nullptr));
    }
  } else if (strcmp(method, "unregisterTexture") == 0) {
    FlValue *args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_INT) {
      int64_t texture_id = fl_value_get_int(args);

      if (self->textures) {
        auto it = self->textures->find(texture_id);
        if (it != self->textures->end()) {
          LadybirdTexture *l_texture = it->second;
          FlTexture *texture = FL_TEXTURE(l_texture);

          set_frame_callback(l_texture->view_id, nullptr, nullptr);

          fl_texture_registrar_unregister_texture(self->texture_registrar,
                                                  texture);
          self->textures->erase(it);
        }
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "Expected int textureId", nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void ladybird_plugin_dispose(GObject *object) {
  LadybirdPlugin *self = LADYBIRD_PLUGIN(object);
  if (self->textures) {
    delete self->textures;
    self->textures = nullptr;
  }
  G_OBJECT_CLASS(ladybird_plugin_parent_class)->dispose(object);
}

static void ladybird_plugin_class_init(LadybirdPluginClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = ladybird_plugin_dispose;
}

static void ladybird_plugin_init(LadybirdPlugin *self) {
  self->textures = new std::map<int64_t, LadybirdTexture *>();
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data) {
  LadybirdPlugin *plugin = LADYBIRD_PLUGIN(user_data);
  ladybird_plugin_handle_method_call(plugin, method_call);
}

void ladybird_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
  LadybirdPlugin *plugin =
      LADYBIRD_PLUGIN(g_object_new(ladybird_plugin_get_type(), nullptr));

  plugin->registrar = registrar;
  plugin->texture_registrar =
      fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "ladybird", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
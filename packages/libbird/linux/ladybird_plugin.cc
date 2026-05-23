#include "include/ladybird/ladybird_plugin.h"

#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <map>

#include "engine.h"
#include "ladybird_plugin_private.h"

struct DmaBufImageSlot {
  EGLDisplay display{EGL_NO_DISPLAY};
  EGLImageKHR image{EGL_NO_IMAGE_KHR};
  int fd{-1};
  dev_t dev{0};
  ino_t ino{0};
  int width{0};
  int height{0};
  int pitch{0};
  uint32_t drm_format{0};
  uint64_t modifier{0};
  bool premultiplied{true};
  uint64_t last_generation{0};
};

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
  std::array<DmaBufImageSlot, 2> dmabuf_slots;
  bool dmabuf_import_disabled;
  bool logged_dmabuf_active;
  bool logged_cpu_fallback;

  uint64_t last_frame_generation;
};

G_DECLARE_FINAL_TYPE(LadybirdTexture, ladybird_texture, LADYBIRD, TEXTURE,
                     FlTextureGL)

G_DEFINE_TYPE(LadybirdTexture, ladybird_texture, fl_texture_gl_get_type())

static void ensure_gl_texture(LadybirdTexture *self);

static void release_dmabuf_slot(DmaBufImageSlot *slot) {
  if (slot->image != EGL_NO_IMAGE_KHR && slot->display != EGL_NO_DISPLAY) {
    eglDestroyImageKHR(slot->display, slot->image);
    slot->image = EGL_NO_IMAGE_KHR;
  }
  if (slot->fd >= 0) {
    ::close(slot->fd);
    slot->fd = -1;
  }
  slot->display = EGL_NO_DISPLAY;
  slot->dev = 0;
  slot->ino = 0;
  slot->width = 0;
  slot->height = 0;
  slot->pitch = 0;
  slot->drm_format = 0;
  slot->modifier = 0;
  slot->premultiplied = true;
  slot->last_generation = 0;
}

static void release_all_dmabuf_slots(LadybirdTexture *self) {
  for (auto &slot : self->dmabuf_slots)
    release_dmabuf_slot(&slot);
}

static int find_dmabuf_slot(LadybirdTexture *self, EGLDisplay display,
                            dev_t dev, ino_t ino, int width, int height,
                            int pitch, uint32_t drm_format, uint64_t modifier,
                            bool premultiplied) {
  for (size_t i = 0; i < self->dmabuf_slots.size(); ++i) {
    auto const &slot = self->dmabuf_slots[i];
    if (slot.image == EGL_NO_IMAGE_KHR)
      continue;
    if (slot.display != display)
      continue;
    if (slot.dev != dev || slot.ino != ino)
      continue;
    if (slot.width != width || slot.height != height || slot.pitch != pitch)
      continue;
    if (slot.drm_format != drm_format || slot.modifier != modifier)
      continue;
    if (slot.premultiplied != premultiplied)
      continue;
    return static_cast<int>(i);
  }
  return -1;
}

static int choose_dmabuf_slot_to_replace(LadybirdTexture *self) {
  for (size_t i = 0; i < self->dmabuf_slots.size(); ++i) {
    if (self->dmabuf_slots[i].image == EGL_NO_IMAGE_KHR)
      return static_cast<int>(i);
  }

  int oldest_index = 0;
  uint64_t oldest_generation = self->dmabuf_slots[0].last_generation;
  for (size_t i = 1; i < self->dmabuf_slots.size(); ++i) {
    if (self->dmabuf_slots[i].last_generation < oldest_generation) {
      oldest_generation = self->dmabuf_slots[i].last_generation;
      oldest_index = static_cast<int>(i);
    }
  }
  return oldest_index;
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
      frame.fd < 0 || frame.width <= 0 || frame.height <= 0 ||
      frame.pitch <= 0) {
    if (!self->logged_cpu_fallback) {
      g_message(
          "[ladybird] view %d: DMA-BUF frame unavailable; using CPU upload "
          "fallback",
          self->view_id);
      self->logged_cpu_fallback = true;
    }
    return false;
  }

  EGLDisplay display = eglGetCurrentDisplay();
  if (!can_import_dmabuf(display)) {
    ::close(frame.fd);
    self->dmabuf_import_disabled = true;
    release_all_dmabuf_slots(self);
    if (!self->logged_cpu_fallback) {
      g_warning(
          "[ladybird] view %d: EGL DMA-BUF import unavailable "
          "(EGL_EXT_image_dma_buf_import=%d, GL_OES_EGL_image=%d); "
          "falling back to CPU uploads",
          self->view_id,
          display != EGL_NO_DISPLAY &&
              epoxy_has_egl_extension(display, "EGL_EXT_image_dma_buf_import"),
          epoxy_has_gl_extension("GL_OES_EGL_image"));
      self->logged_cpu_fallback = true;
    }
    return false;
  }

  struct stat st = {};
  if (::fstat(frame.fd, &st) != 0) {
    ::close(frame.fd);
    return false;
  }

  int slot_index = find_dmabuf_slot(
      self, display, st.st_dev, st.st_ino, frame.width, frame.height,
      frame.pitch, frame.drm_format, frame.modifier, frame.premultiplied);

  if (slot_index < 0) {
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
      auto egl_error = eglGetError();
      ::close(frame.fd);
      if (!self->logged_cpu_fallback) {
        g_warning("[ladybird] view %d: eglCreateImageKHR dma-buf import failed "
                  "(error=0x%04x); using CPU uploads",
                  self->view_id, static_cast<unsigned>(egl_error));
        self->logged_cpu_fallback = true;
      }
      return false;
    }

    slot_index = choose_dmabuf_slot_to_replace(self);
    auto &slot = self->dmabuf_slots[slot_index];
    release_dmabuf_slot(&slot);
    slot.display = display;
    slot.image = image;
    slot.fd = frame.fd;
    slot.dev = st.st_dev;
    slot.ino = st.st_ino;
    slot.width = frame.width;
    slot.height = frame.height;
    slot.pitch = frame.pitch;
    slot.drm_format = frame.drm_format;
    slot.modifier = frame.modifier;
    slot.premultiplied = frame.premultiplied;
  } else {
    ::close(frame.fd);
  }

  auto &slot = self->dmabuf_slots[slot_index];
  slot.last_generation = frame.generation;

  ensure_gl_texture(self);
  glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, slot.image);

  self->texture_width = slot.width;
  self->texture_height = slot.height;

  if (!self->logged_dmabuf_active) {
    g_message(
        "[ladybird] view %d: DMA-BUF zero-copy path active (%dx%d pitch=%d "
        "drm=0x%08x mod=0x%llx)",
        self->view_id, slot.width, slot.height, slot.pitch, slot.drm_format,
        static_cast<unsigned long long>(slot.modifier));
    self->logged_dmabuf_active = true;
  }

  *target = GL_TEXTURE_2D;
  *name = self->texture_name;
  *width = static_cast<uint32_t>(slot.width);
  *height = static_cast<uint32_t>(slot.height);
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
  release_all_dmabuf_slots(self);
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
  for (auto &slot : self->dmabuf_slots)
    slot = DmaBufImageSlot{};
  self->dmabuf_import_disabled = false;
  self->logged_dmabuf_active = false;
  self->logged_cpu_fallback = false;
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
static constexpr guint kLadybirdTickIntervalMs = 4;

static void ladybird_frame_ready_callback(void *context) {
  auto *texture = static_cast<LadybirdTexture *>(context);
  if (!texture || !texture->texture_registrar)
    return;

  texture->last_frame_generation = get_frame_generation(texture->view_id);
  fl_texture_registrar_mark_texture_frame_available(texture->texture_registrar,
                                                    FL_TEXTURE(texture));
}

static gboolean ladybird_tick_callback(gpointer user_data) {
  (void)user_data;
  tick_ladybird();
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

      // Drive texture presentation directly from native frame readiness.
      set_frame_callback((int)view_id, ladybird_frame_ready_callback, texture);

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
    for (auto const &it : *self->textures) {
      if (!it.second)
        continue;
      set_frame_callback(it.second->view_id, nullptr, nullptr);
      fl_texture_registrar_unregister_texture(self->texture_registrar,
                                              FL_TEXTURE(it.second));
    }
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
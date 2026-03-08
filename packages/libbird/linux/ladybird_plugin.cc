#include "include/ladybird/ladybird_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>
#include <cstdio>
#include <map>

#include "ladybird_plugin_private.h"
#include "engine.h"
#include <iostream>

// --- LadybirdTexture ---

struct _LadybirdTexture
{
  FlPixelBufferTexture parent_instance;
  int view_id;
  FlTextureRegistrar *texture_registrar;
};

G_DECLARE_FINAL_TYPE(LadybirdTexture, ladybird_texture, LADYBIRD, TEXTURE, FlPixelBufferTexture)

G_DEFINE_TYPE(LadybirdTexture, ladybird_texture, fl_pixel_buffer_texture_get_type())

static gboolean ladybird_texture_copy_pixels(FlPixelBufferTexture *texture,
                                             const uint8_t **out_buffer,
                                             uint32_t *width,
                                             uint32_t *height,
                                             GError **error)
{
  // This works so that's odd
  // static uint8_t *dummy_buffer = nullptr;
  // if (!dummy_buffer)
  // {
  //   dummy_buffer = new uint8_t[100 * 100 * 4];
  //   for (int i = 0; i < 100 * 100; i++)
  //   {
  //     dummy_buffer[i * 4 + 0] = 255; // R
  //     dummy_buffer[i * 4 + 1] = 0;   // G
  //     dummy_buffer[i * 4 + 2] = 0;   // B
  //     dummy_buffer[i * 4 + 3] = 255; // A
  //   }
  // }
  // *out_buffer = dummy_buffer;
  // *width = 100;
  // *height = 100;
  // return TRUE;

  g_print("Creating ladybird texture\n");
  LadybirdTexture *self = LADYBIRD_TEXTURE(texture);
  g_print("created\n!");

  void *pixels = get_latest_pixel_buffer(self->view_id);
  g_print("got buffer\n");
  int w = get_iosurface_width(self->view_id);
  int h = get_iosurface_height(self->view_id);
  g_print("got size\n");

  if (!pixels || w <= 0 || h <= 0)
  {
    g_print("not pixels\n");
    if (width)
      *width = 0;
    if (height)
      *height = 0;
    return FALSE;
  }

  *out_buffer = (const uint8_t *)pixels;
  *width = w;
  *height = h;

  g_print("exiting as true\n");
  return TRUE;
}

static void ladybird_texture_class_init(LadybirdTextureClass *klass)
{
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = ladybird_texture_copy_pixels;
}

static void ladybird_texture_init(LadybirdTexture *self)
{
  self->view_id = -1;
  self->texture_registrar = nullptr;
}

static LadybirdTexture *ladybird_texture_new(int view_id, FlTextureRegistrar *registrar)
{
  LadybirdTexture *self = LADYBIRD_TEXTURE(g_object_new(ladybird_texture_get_type(), nullptr));
  self->view_id = view_id;
  self->texture_registrar = registrar;
  return self;
}

// --- LadybirdPlugin ---

#define LADYBIRD_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), ladybird_plugin_get_type(), \
                              LadybirdPlugin))

struct _LadybirdPlugin
{
  GObject parent_instance;
  FlPluginRegistrar *registrar;
  FlTextureRegistrar *texture_registrar;
  std::map<int64_t, LadybirdTexture *> *textures;
};

G_DEFINE_TYPE(LadybirdPlugin, ladybird_plugin, g_object_get_type())

static bool g_ladybird_initialized = false;

static gboolean ladybird_tick_callback(gpointer user_data)
{
  tick_ladybird();
  return G_SOURCE_CONTINUE;
}

static void frame_available_callback(void *context)
{
  LadybirdTexture *texture = LADYBIRD_TEXTURE(context);
  if (texture && texture->texture_registrar)
  {
    fl_texture_registrar_mark_texture_frame_available(texture->texture_registrar, FL_TEXTURE(texture));
  }
}

static void ladybird_plugin_handle_method_call(
    LadybirdPlugin *self,
    FlMethodCall *method_call)
{
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar *method = fl_method_call_get_name(method_call);

  if (!g_ladybird_initialized)
  {
    init_ladybird();
    g_ladybird_initialized = true;
    g_timeout_add(16, ladybird_tick_callback, nullptr);
  }

  if (strcmp(method, "getPlatformVersion") == 0)
  {
    struct utsname uname_data = {};
    uname(&uname_data);
    g_autofree gchar *version = g_strdup_printf("Linux %s", uname_data.version);
    g_autoptr(FlValue) result = fl_value_new_string(version);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }
  else if (strcmp(method, "createTexture") == 0)
  {
    FlValue *args = fl_method_call_get_args(method_call);

    if (fl_value_get_type(args) == FL_VALUE_TYPE_INT)
    {
      int64_t view_id = fl_value_get_int(args);

      LadybirdTexture *texture = ladybird_texture_new((int)view_id, self->texture_registrar);
      fl_texture_registrar_register_texture(self->texture_registrar, FL_TEXTURE(texture));

      set_frame_callback((int)view_id, frame_available_callback, texture);

      int64_t texture_id = (int64_t)fl_texture_get_id(FL_TEXTURE(texture));

      if (self->textures)
      {
        self->textures->insert(std::make_pair(texture_id, texture));
      }

      g_autoptr(FlValue) result = fl_value_new_int(texture_id);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
    else
    {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Expected int viewId", nullptr));
    }
  }
  else if (strcmp(method, "unregisterTexture") == 0)
  {
    FlValue *args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) == FL_VALUE_TYPE_INT)
    {
      int64_t texture_id = fl_value_get_int(args);

      if (self->textures)
      {
        auto it = self->textures->find(texture_id);
        if (it != self->textures->end())
        {
          LadybirdTexture *l_texture = it->second;
          FlTexture *texture = FL_TEXTURE(l_texture);

          set_frame_callback(l_texture->view_id, nullptr, nullptr);

          fl_texture_registrar_unregister_texture(self->texture_registrar, texture);
          self->textures->erase(it);
        }
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    else
    {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "Expected int textureId", nullptr));
    }
  }
  else
  {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void ladybird_plugin_dispose(GObject *object)
{
  LadybirdPlugin *self = LADYBIRD_PLUGIN(object);
  if (self->textures)
  {
    delete self->textures;
    self->textures = nullptr;
  }
  G_OBJECT_CLASS(ladybird_plugin_parent_class)->dispose(object);
}

static void ladybird_plugin_class_init(LadybirdPluginClass *klass)
{
  G_OBJECT_CLASS(klass)->dispose = ladybird_plugin_dispose;
}

static void ladybird_plugin_init(LadybirdPlugin *self)
{
  self->textures = new std::map<int64_t, LadybirdTexture *>();
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data)
{
  LadybirdPlugin *plugin = LADYBIRD_PLUGIN(user_data);
  ladybird_plugin_handle_method_call(plugin, method_call);
}

void ladybird_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
  LadybirdPlugin *plugin = LADYBIRD_PLUGIN(
      g_object_new(ladybird_plugin_get_type(), nullptr));

  plugin->registrar = registrar;
  plugin->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "ladybird",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
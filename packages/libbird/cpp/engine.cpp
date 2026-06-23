#include "engine.h"
#include "LibWebView/Application.h"
#include <cstdio>
#include <memory>
#include <mutex>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Platform-specific backend header.  All __APPLE__ ifdefs live here and
// in the on_ready_to_paint lambda — nowhere else in this file.
#ifdef __APPLE__
#include "platform/macos_view_backend.h"
#include <IOSurface/IOSurface.h>
#else
#include "platform/linux_view_backend.h"
#endif

#include <AK/BitCast.h>
#include <AK/HashMap.h>
#include <AK/JsonArray.h>
#include <AK/JsonObject.h>
#include <AK/LexicalPath.h>
#include <AK/OwnPtr.h>
#include <AK/StringView.h>
#include <LibCore/EventLoop.h>
#include <LibCore/ResourceImplementation.h>
#include <LibCore/ResourceImplementationFile.h>
#include <LibCore/System.h>
#include <LibCore/ThreadEventQueue.h>
#include <LibGfx/Bitmap.h>
#include <LibGfx/SharedImageBuffer.h>
#include <LibGfx/SystemTheme.h>
#include <LibMain/Main.h>
#include <LibURL/Parser.h>
#include <LibURL/URL.h>
#include <LibWeb/Page/InputEvent.h>
#include <LibWeb/PixelUnits.h>
#include <LibWebView/BrowserProcess.h>
#include <LibWebView/HistoryStore.h>
#include <LibWebView/Menu.h>
#include <LibWebView/Utilities.h>
#include <LibWebView/ViewImplementation.h>
#ifndef __APPLE__
#include <unistd.h>
#endif

namespace IPC {

template <> ErrorOr<void> encode(Encoder &encoder, float const &value) {
  return encoder.encode(AK::bit_cast<u32>(value));
}

template <> ErrorOr<void> encode(Encoder &encoder, double const &value) {
  return encoder.encode(AK::bit_cast<u64>(value));
}

} // namespace IPC

int g_next_view_id = 1;
int g_active_view_id = -1;

AskUserForDownloadPathCallback g_ask_user_for_download_path_callback = nullptr;
DisplayDownloadConfirmationDialogCallback
    g_display_download_confirmation_dialog_callback = nullptr;
DisplayErrorDialogCallback g_display_error_dialog_callback = nullptr;

// ---------------------------------------------------------------------------
// Platform backend factory
// ---------------------------------------------------------------------------

static std::unique_ptr<ViewBackend> create_view_backend() {
#ifdef __APPLE__
  return std::make_unique<MacOSViewBackend>();
#else
  return std::make_unique<LinuxViewBackend>();
#endif
}

// ---------------------------------------------------------------------------
// FlutterViewImpl
// ---------------------------------------------------------------------------

class FlutterViewImpl final : public WebView::ViewImplementation {
public:
  static constexpr double kDefaultRefreshRate = 60.0;

  enum class MacFrameSource {
    Unknown,
    IOSurface,
    BitmapFallback,
  };

  static ErrorOr<NonnullOwnPtr<FlutterViewImpl>> create(int view_id) {
    return adopt_nonnull_own_or_enomem(new (std::nothrow)
                                           FlutterViewImpl(view_id));
  }

  int m_view_id;
  double m_zoom{1.0};

  // Viewport dimensions — updated by resize() so viewport_size() always
  // returns the currently-requested render size, not the last painted size.
  int m_viewport_width{800};
  int m_viewport_height{600};

  // Platform rendering backend (LinuxViewBackend / MacOSViewBackend).
  std::unique_ptr<ViewBackend> m_backend;
  uint64_t m_debug_paint_event_count{0};
  Optional<u64> m_display_id;
  double m_display_refresh_rate{kDefaultRefreshRate};

#ifdef __APPLE__
  MacFrameSource m_last_mac_frame_source{MacFrameSource::Unknown};
#endif

  // Mutex for the non-frame callbacks (URL, title, favicon, loading state).
  std::mutex m_info_mutex;

  UrlChangeCallback m_url_change_callback = nullptr;
  TitleChangeCallback m_title_change_callback = nullptr;
  FaviconChangeCallback m_favicon_change_callback = nullptr;
  CrossSiteNavigationCallback m_cross_site_navigation_callback = nullptr;
  LoadingStateChangeCallback m_loading_state_change_callback = nullptr;
  CursorChangeCallback m_cursor_change_callback = nullptr;
  ContextMenuRequestCallback m_context_menu_request_callback = nullptr;
  NewWebViewCallback m_new_web_view_callback = nullptr;
  bool m_is_loading{false};

  std::mutex m_context_menu_mutex;
  HashMap<int, WeakPtr<WebView::Action>> m_context_menu_actions;
  int m_next_context_menu_action_token{1};

  static int to_cursor_type_for_flutter(Gfx::Cursor const &cursor) {
    return cursor.visit(
        [](Gfx::StandardCursor standard) { return static_cast<int>(standard); },
        [](Gfx::ImageCursor const &) {
          // Flutter cannot consume custom pixel cursors via this API, so use
          // a standard fallback.
          return static_cast<int>(Gfx::StandardCursor::Arrow);
        });
  }

  int register_context_menu_action(
      NonnullRefPtr<WebView::Action> const &action) {
    int token = m_next_context_menu_action_token++;
    m_context_menu_actions.set(token, action->make_weak_ptr());
    return token;
  }

  JsonArray serialize_context_menu_items(WebView::Menu const &menu) {
    JsonArray items;

    for (auto const &menu_item : menu.items()) {
      menu_item.visit(
          [&](NonnullRefPtr<WebView::Action> const &action) {
            if (!action->visible())
              return;

            JsonObject item;
            item.set("kind"sv, "action"sv);
            item.set("token"sv, register_context_menu_action(action));
            item.set("text"sv, action->text());
            item.set("enabled"sv, action->enabled());
            item.set("checkable"sv, action->is_checkable());
            if (action->is_checkable())
              item.set("checked"sv, action->checked());
            items.must_append(move(item));
          },
          [&](NonnullRefPtr<WebView::Menu> const &submenu) {
            if (!submenu->visible())
              return;

            JsonObject item;
            item.set("kind"sv, "submenu"sv);
            item.set("text"sv, submenu->title());
            item.set("items"sv,
                     JsonValue(serialize_context_menu_items(*submenu)));
            items.must_append(move(item));
          },
          [&](WebView::Separator) {
            JsonObject item;
            item.set("kind"sv, "separator"sv);
            items.must_append(move(item));
          });
    }

    return items;
  }

  void dispatch_context_menu_request(StringView type, Gfx::IntPoint position,
                                     WebView::Menu &menu) {
    ContextMenuRequestCallback callback = nullptr;
    char *payload = nullptr;

    {
      std::lock_guard lock(m_context_menu_mutex);
      m_context_menu_actions.clear();

      JsonObject request;
      request.set("type"sv, type);
      request.set("x"sv, position.x());
      request.set("y"sv, position.y());
      request.set("items"sv, JsonValue(serialize_context_menu_items(menu)));

      auto serialized = JsonValue(move(request)).serialized();
      auto bytes = serialized.to_byte_string();
      payload = strdup(bytes.characters());
      callback = m_context_menu_request_callback;
    }

    if (!payload)
      return;

    if (callback)
      callback(m_view_id, payload);
    else
      free(payload);
  }

  void set_context_menu_request_callback(ContextMenuRequestCallback callback) {
    std::lock_guard lock(m_context_menu_mutex);
    m_context_menu_request_callback = callback;
    if (!callback)
      m_context_menu_actions.clear();
  }

  String create_child_web_view_handle(Optional<u64> page_index,
                                      int &new_view_id);

  bool activate_context_menu_action(int action_token) {
    WeakPtr<WebView::Action> weak_action;

    {
      std::lock_guard lock(m_context_menu_mutex);
      auto it = m_context_menu_actions.find(action_token);
      if (it == m_context_menu_actions.end())
        return false;
      weak_action = it->value;
    }

    auto action = weak_action.strong_ref();
    if (!action || !action->visible() || !action->enabled())
      return false;

    action->activate();

    std::lock_guard lock(m_context_menu_mutex);
    m_context_menu_actions.clear();
    return true;
  }

  void update_loading_state(bool is_loading) {
    if (m_is_loading == is_loading)
      return;

    m_is_loading = is_loading;

    std::lock_guard lock(m_info_mutex);
    if (m_loading_state_change_callback)
      m_loading_state_change_callback(m_is_loading);
  }

  void sync_device_pixel_ratio() { m_device_pixel_ratio = m_zoom; }

  void configure_client_process() {
    auto theme_path = LexicalPath::join(WebView::s_ladybird_resource_root,
                                        "themes"sv, "Default.ini"sv);
    auto theme = Gfx::load_system_theme(theme_path.string())
                     .release_value_but_fixme_should_propagate_errors();

    sync_device_pixel_ratio();
    client().async_update_system_theme(m_client_state.page_index, theme);
    client().async_set_viewport(m_client_state.page_index, viewport_size(),
                                m_device_pixel_ratio, is_fullscreen());
    client().async_set_window_size(m_client_state.page_index, viewport_size());
    client().async_set_maximum_frames_per_second(m_client_state.page_index,
                                                 m_maximum_frames_per_second);

    auto compositor_context_id =
        client().compositor_context_id_for_page(m_client_state.page_index);
    WebView::Application::the().update_compositor_display_metadata(
        compositor_context_id, m_display_id, m_display_refresh_rate);

    Web::DevicePixelRect screen_rect{0, 0, 1920, 1080};
    client().async_update_screen_rects(m_client_state.page_index,
                                       {{screen_rect}}, 0);
  }

  void set_display_metadata(Optional<u64> display_id, double refresh_rate,
                            double maximum_frames_per_second) {
    auto const sanitized_refresh_rate =
        refresh_rate > 0.0 ? refresh_rate : 60.0;
    auto const sanitized_maximum_frames_per_second =
        maximum_frames_per_second > 0.0 ? maximum_frames_per_second
                                        : sanitized_refresh_rate;

    m_display_id = display_id;
    m_display_refresh_rate = sanitized_refresh_rate;
    m_maximum_frames_per_second = sanitized_maximum_frames_per_second;

    if (!m_client_state.client)
      return;

    client().async_set_maximum_frames_per_second(m_client_state.page_index,
                                                 m_maximum_frames_per_second);
    WebView::Application::the().update_compositor_display_metadata(
        client().compositor_context_id_for_page(m_client_state.page_index),
        m_display_id, m_display_refresh_rate);
  }

  virtual void initialize_client(
      CreateNewClient create_new_client = CreateNewClient::Yes) override {

    ViewImplementation::initialize_client(create_new_client);
    configure_client_process();
    set_system_visibility_state(Web::HTML::VisibilityState::Visible);

    // -----------------------------------------------------------------------
    // on_ready_to_paint — modelled after Qt's WebContentView pattern.
    //
    // Linux path consumes bitmap/dmabuf. macOS first tries IOSurface for the
    // zero-copy external-texture path, then falls back to bitmap conversion.
    // -----------------------------------------------------------------------
    on_ready_to_paint = [this]() {
      if (!m_client_state.has_usable_bitmap ||
          !m_client_state.front_bitmap.shared_image_buffer)
        return;

      ++m_debug_paint_event_count;

      auto *shared_image_buffer =
          m_client_state.front_bitmap.shared_image_buffer.ptr();

#ifndef __APPLE__
#ifdef USE_VULKAN_DMABUF_IMAGES
      auto *linux_backend = static_cast<LinuxViewBackend *>(m_backend.get());
      if (auto const &dmabuf = shared_image_buffer->linux_dmabuf_handle();
          dmabuf.has_value()) {
        linux_backend->set_linux_dmabuf_frame(
            dmabuf->file.fd(), dmabuf->size.width(), dmabuf->size.height(),
            static_cast<int>(dmabuf->pitch), dmabuf->drm_format,
            dmabuf->modifier,
            dmabuf->alpha_type == Gfx::AlphaType::Premultiplied);
      } else {
        linux_backend->clear_linux_dmabuf_frame();
      }
#endif
#else
      auto *mac_backend = static_cast<MacOSViewBackend *>(m_backend.get());
      auto *surface = static_cast<IOSurfaceRef>(
          shared_image_buffer->iosurface_handle().core_foundation_pointer());
      if (surface) {
        auto surface_width = static_cast<int>(IOSurfaceGetWidth(surface));
        auto surface_height = static_cast<int>(IOSurfaceGetHeight(surface));
        if (surface_width <= 0 || surface_height <= 0) {
          auto bitmap_size =
              m_client_state.front_bitmap.last_painted_size.to_type<int>();
          surface_width = bitmap_size.width();
          surface_height = bitmap_size.height();
        }

        if (mac_backend->on_iosurface_ready(surface, surface_width,
                                            surface_height)) {
          if (m_last_mac_frame_source != MacFrameSource::IOSurface) {
            std::fprintf(
                stderr,
                "[Ladybird][macOS] View %d rendering source: IOSurface\n",
                m_view_id);
            m_last_mac_frame_source = MacFrameSource::IOSurface;
          }
          if ((m_debug_paint_event_count % 30) == 1) {
            auto const &bitmap_size =
                m_client_state.front_bitmap.last_painted_size.to_type<int>();
            std::fprintf(
                stderr,
                "[Ladybird][engine] view=%d paint#=%llu source=IOSurface "
                "surface_size=%dx%d bitmap_size=%dx%d viewport_size=%dx%d "
                "m_zoom=%f\n",
                m_view_id,
                static_cast<unsigned long long>(m_debug_paint_event_count),
                surface_width, surface_height, bitmap_size.width(),
                bitmap_size.height(), m_viewport_width, m_viewport_height,
                m_zoom);
          }
          return;
        }
      }
#endif

      // hmm
      //
      if (!shared_image_buffer) {
        return;
      }
      auto bitmap =
          AK::RefPtr<Gfx::Bitmap const>(shared_image_buffer->bitmap());
      m_backend->on_bitmap_ready(std::move(bitmap));

      if ((m_debug_paint_event_count % 120) == 1) {
        std::fprintf(
            stderr,
            "[Ladybird][engine] view=%d paint#=%llu source=Bitmap size=%dx%d "
            "gen=%llu\n",
            m_view_id,
            static_cast<unsigned long long>(m_debug_paint_event_count),
            m_backend->width(), m_backend->height(),
            static_cast<unsigned long long>(m_backend->frame_generation()));
      }

#ifdef __APPLE__
      if (m_last_mac_frame_source != MacFrameSource::BitmapFallback) {
        std::fprintf(
            stderr,
            "[Ladybird][macOS] View %d rendering source: Bitmap fallback\n",
            m_view_id);
        m_last_mac_frame_source = MacFrameSource::BitmapFallback;
      }
#endif
    };

    on_web_content_process_change_for_cross_site_navigation = [this]() {
      std::fprintf(stderr,
                   "WebContent process changed for cross site navigation.\n");
      configure_client_process();
      std::lock_guard lock(m_info_mutex);
      if (m_cross_site_navigation_callback)
        m_cross_site_navigation_callback(m_view_id);
    };

    on_web_content_crashed = [this]() {
      std::fprintf(stderr, "WebContent process crashed.\n");
      update_loading_state(false);
    };

    on_load_start = [this](URL::URL const &, bool) {
      update_loading_state(true);
    };

    on_load_finish = [this](URL::URL const &) { update_loading_state(false); };

    on_url_change = [this](URL::URL const &url) {
      std::lock_guard lock(m_info_mutex);
      if (m_url_change_callback) {
        auto url_string = url.to_string().to_byte_string();
        m_url_change_callback(strdup(url_string.characters()));
      }
    };

    on_title_change = [this](Utf16String const &title) {
      std::lock_guard lock(m_info_mutex);
      if (m_title_change_callback) {
        auto title_string = title.to_utf8().to_byte_string();
        m_title_change_callback(strdup(title_string.characters()));
      }
    };

    on_favicon_change = [this](Gfx::Bitmap const &bitmap) {
      std::lock_guard lock(m_info_mutex);
      if (m_favicon_change_callback) {
        size_t length = bitmap.width() * bitmap.height() * 4;
        uint8_t *buffer = (uint8_t *)malloc(length);
        memcpy(buffer, reinterpret_cast<const uint8_t *>(bitmap.begin()),
               length);
        m_favicon_change_callback(buffer, bitmap.width(), bitmap.height());
      }
    };

    on_cursor_change = [this](Gfx::Cursor const &cursor) {
      std::lock_guard lock(m_info_mutex);
      if (m_cursor_change_callback)
        m_cursor_change_callback(to_cursor_type_for_flutter(cursor));
    };

    on_new_web_view = [this](Web::HTML::ActivateTab activate_tab,
                             Web::HTML::WebViewHints,
                             Optional<u64> page_index) -> String {
      int new_view_id = -1;
      auto handle = create_child_web_view_handle(page_index, new_view_id);
      if (handle.is_empty())
        return {};

      NewWebViewCallback callback = nullptr;
      {
        std::lock_guard lock(m_info_mutex);
        callback = m_new_web_view_callback;
      }

      if (callback)
        callback(new_view_id, activate_tab == Web::HTML::ActivateTab::Yes);

      return handle;
    };

    page_context_menu().on_activation = [this](Gfx::IntPoint position) {
      dispatch_context_menu_request("page"sv, position, page_context_menu());
    };
    link_context_menu().on_activation = [this](Gfx::IntPoint position) {
      dispatch_context_menu_request("link"sv, position, link_context_menu());
    };
    image_context_menu().on_activation = [this](Gfx::IntPoint position) {
      dispatch_context_menu_request("image"sv, position, image_context_menu());
    };
    media_context_menu().on_activation = [this](Gfx::IntPoint position) {
      dispatch_context_menu_request("media"sv, position, media_context_menu());
    };
  }

  void resize(int width, int height) {
    std::fprintf(stderr, "[LibBird] resize: incoming %dx%d, m_zoom: %f\n",
                 width, height, m_zoom);
    m_viewport_width = width;
    m_viewport_height = height;
    auto size = Web::DevicePixelSize{width, height};
    sync_device_pixel_ratio();
    client().async_set_viewport(m_client_state.page_index, size,
                                m_device_pixel_ratio, is_fullscreen());
    client().async_set_window_size(m_client_state.page_index, size);
    WebView::Application::the().update_compositor_viewport(
        client().compositor_context_id_for_page(m_client_state.page_index),
        viewport_size().to_type<int>(),
        Web::Compositor::WindowResizingInProgress::Yes);
  }

  void update_zoom_scale() {
    std::fprintf(stderr, "[LibBird] update_zoom_scale: m_zoom: %f\n", m_zoom);
    sync_device_pixel_ratio();
    client().async_set_viewport(m_client_state.page_index, viewport_size(),
                                m_device_pixel_ratio, is_fullscreen());
  }

  void dispatch_mouse_event(Web::MouseEvent::Type type, int x, int y,
                            int button, int buttons, int modifiers,
                            double wheel_delta_x, double wheel_delta_y) {
    Web::DevicePixelPoint position = {x, y};
    Web::DevicePixelPoint screen_position = {x, y};
    enqueue_input_event(
        Web::MouseEvent{type, position, screen_position,
                        static_cast<Web::UIEvents::MouseButton>(button),
                        static_cast<Web::UIEvents::MouseButton>(buttons),
                        static_cast<Web::UIEvents::KeyModifier>(modifiers),
                        wheel_delta_x, wheel_delta_y,
                        type == Web::MouseEvent::Type::MouseDown ||
                                type == Web::MouseEvent::Type::MouseUp
                            ? 1
                            : 0,
                        nullptr});
  }

  void dispatch_key_event(Web::KeyEvent::Type type, int keycode, int modifiers,
                          uint32_t code_point, bool repeat) {
    enqueue_input_event(
        Web::KeyEvent{type, static_cast<Web::UIEvents::KeyCode>(keycode),
                      static_cast<Web::UIEvents::KeyModifier>(modifiers),
                      // TODO: implement should_insert_text
                      code_point, repeat, false});
  }

  virtual ~FlutterViewImpl() = default;

private:
  explicit FlutterViewImpl(int view_id) : m_view_id(view_id) {
    m_backend = create_view_backend();
  }

  virtual Web::DevicePixelSize viewport_size() const override {
    return {m_viewport_width, m_viewport_height};
  }
  virtual Gfx::IntPoint
  to_content_position(Gfx::IntPoint widget_position) const override {
    return widget_position;
  }
  virtual Gfx::IntPoint
  to_widget_position(Gfx::IntPoint content_position) const override {
    return content_position;
  }
};

#include <map>
// View registry — owns all FlutterViewImpl instances.
static std::map<int, AK::OwnPtr<FlutterViewImpl>> g_web_views;

String FlutterViewImpl::create_child_web_view_handle(Optional<u64> page_index,
                                                     int &new_view_id) {
  new_view_id = -1;

  auto created_view = FlutterViewImpl::create(g_next_view_id++).release_value();
  if (page_index.has_value()) {
    created_view->m_client_state.client = client();
    created_view->m_client_state.page_index = page_index.value();
    created_view->initialize_client(CreateNewClient::No);
  } else {
    created_view->initialize_client(CreateNewClient::Yes);
  }

  new_view_id = created_view->m_view_id;
  auto handle = created_view->handle();
  g_web_views[new_view_id] = std::move(created_view);
  return handle;
}

class FlutterApplication : public WebView::Application {
  WEB_VIEW_APPLICATION(FlutterApplication)

public:
  FlutterApplication(Optional<ByteString> ladybird_binary_path = {})
      : WebView::Application(std::move(ladybird_binary_path)) {}

  virtual ~FlutterApplication() override = default;

  virtual void create_platform_arguments(Core::ArgsParser &) override {}
  virtual void create_platform_options(WebView::BrowserOptions &,
                                       WebView::RequestServerOptions &,
                                       WebView::WebContentOptions &) override {}

  virtual bool should_capture_web_content_output() const override {
    return false;
  }

  virtual Core::EventLoop &create_platform_event_loop() override {
    return WebView::Application::create_platform_event_loop();
  }

  virtual Optional<WebView::ViewImplementation &>
  active_web_view() const override {
    if (g_active_view_id != -1) {
      auto it = g_web_views.find(g_active_view_id);
      if (it != g_web_views.end())
        return *it->second;
    }
    if (!g_web_views.empty()) {
      return *g_web_views.begin()->second;
    }
    return {};
  }

  virtual Optional<WebView::ViewImplementation &>
  open_blank_new_tab(Web::HTML::ActivateTab) const override {
    return {};
  }
  virtual Optional<ByteString>
  ask_user_for_download_path(StringView suggestion) const override {
    if (g_ask_user_for_download_path_callback) {
      auto suggestion_string = suggestion.to_byte_string();
      char *result =
          g_ask_user_for_download_path_callback(suggestion_string.characters());
      if (result) {
        ByteString path(result);
        free(result);
        return path;
      }
    }
    return {};
  }
  virtual void display_download_confirmation_dialog(
      StringView path, LexicalPath const &lexical_path) const override {
    if (g_display_download_confirmation_dialog_callback) {
      auto path_string = path.to_byte_string();
      g_display_download_confirmation_dialog_callback(
          path_string.characters(), lexical_path.string().characters());
    }
  }
  virtual void display_error_dialog(StringView message) const override {
    if (g_display_error_dialog_callback) {
      auto message_string = message.to_byte_string();
      g_display_error_dialog_callback(message_string.characters());
    }
  }

  // todo: figure out what "Selection" is
  virtual Utf16String clipboard_text(ClipboardType type) const override {
    return WebView::Application::clipboard_text();
  }
  virtual Vector<Web::Clipboard::SystemClipboardRepresentation>
  clipboard_entries() const override {
    return WebView::Application::clipboard_entries();
  }
  virtual void insert_clipboard_entry(
      Web::Clipboard::SystemClipboardRepresentation entry) override {
    WebView::Application::insert_clipboard_entry(std::move(entry));
  }
};

static AK::OwnPtr<FlutterApplication> s_app;
static AK::OwnPtr<WebView::BrowserProcess> s_browser_process;

struct LatestFrameHandle {
  AK::RefPtr<Gfx::Bitmap const> bitmap;
  int width{0};
  int height{0};
  int pitch{0};
  uint64_t generation{0};
};

void init_ladybird() {
  static bool initialized = false;
  if (initialized)
    return;

  initialized = true;

  AK::set_rich_debug_enabled(true);

  Optional<ByteString> lib_path;

#ifdef __APPLE__
  // Do nothing on macos, it should default properly
#else
  auto current_executable_path = Core::System::current_executable_path();
  if (!current_executable_path.is_error()) {
    auto path = current_executable_path.value();
    auto app_dir = LexicalPath::dirname(path);
    lib_path = LexicalPath::join(app_dir, "lib"sv).string();

    // Use share/Lagom in the bundle as resource root
    auto resource_root =
        LexicalPath::join(app_dir, "share"sv, "Lagom"sv).string();
    WebView::s_ladybird_resource_root = resource_root;
    Core::ResourceImplementation::install(
        make<Core::ResourceImplementationFile>(
            MUST(String::from_byte_string(resource_root))));
  } else {
    fprintf(stderr, "[Ladybird] Failed to get executable path: %d\n",
            current_executable_path.error().code());
  }
#endif

  static char const *argv[] = {"Ladybird", nullptr};

  // TODO: I don't really know what this means?
  static AK::StringView string_views[] = {AK::StringView("Ladybird", 8)};
  Main::Arguments arguments = {1, (char **)argv, {string_views, 1}};

  auto app = FlutterApplication::create(arguments, lib_path);
  if (app.is_error()) {
    std::fprintf(stderr, "Failed to construct Ladybird Engine Application\n");
    return;
  }
  s_app = app.release_value();

  s_browser_process = make<WebView::BrowserProcess>();

  if (auto const &browser_options = WebView::Application::browser_options();
      !browser_options.headless_mode.has_value()) {
    if (browser_options.force_new_process == WebView::ForceNewProcess::No) {
      auto disposition = s_browser_process->connect(browser_options.raw_urls,
                                                    browser_options.new_window);

      if (!disposition.is_error() &&
          disposition.value() ==
              WebView::BrowserProcess::ProcessDisposition::ExitProcess) {
        std::fprintf(stderr, "Opening in existing process\n");
        return;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Event-loop tick — inspired by GTK's EventLoopImplementationGtk::pump():
//
//   result  = ThreadEventQueue::current().process();   // pre-drain
//   g_main_context_iteration(ctx, FALSE);              // platform poll
//   result += ThreadEventQueue::current().process();   // post-drain
//
// The pre-drain step flushes any events already posted to the queue (e.g.
// IPC messages received between the previous tick and this one).  The pump
// call exercises EventLoopImplementationUnix::wait_for_events() which does
// a non-blocking poll(2) over all registered notifiers (WebContent /
// RequestServer IPC sockets, timers, etc.).  The post-drain picks up
// anything that was enqueued during that poll.
// ---------------------------------------------------------------------------
extern "C" void tick_ladybird() {
  // Pre-drain: flush events queued since last tick.
  Core::ThreadEventQueue::current().process();

  // Non-blocking IO poll + timer dispatch.
  if (Core::EventLoop::is_running())
    Core::EventLoop::current().pump(Core::EventLoop::WaitMode::PollForEvents);

  // Post-drain: flush whatever the poll triggered.
  Core::ThreadEventQueue::current().process();
}

int create_web_view() {
  int id = g_next_view_id++;
  auto view = FlutterViewImpl::create(id).release_value();
  view->initialize_client();
  g_web_views[id] = std::move(view);
  if (g_active_view_id == -1)
    g_active_view_id = id;
  return id;
}

void destroy_web_view(int view_id) {
  if (g_active_view_id == view_id)
    g_active_view_id = -1;
  g_web_views.erase(view_id);
}

void *get_latest_pixel_buffer(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end()) {
    std::printf("get_latest_pixel_buffer: view %d not found\n", view_id);
    return nullptr;
  }
  return it->second->m_backend->pixel_data();
}

bool copy_latest_pixel_buffer(int view_id, uint8_t *out_buffer,
                              int out_capacity, int *out_width,
                              int *out_height) {
  if (!out_buffer || !out_width || !out_height || out_capacity <= 0)
    return false;

  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;

  int width = 0;
  int height = 0;
  bool copied = it->second->m_backend->copy_pixels_into(
      out_buffer, static_cast<size_t>(out_capacity), width, height);
  if (!copied)
    return false;

  *out_width = width;
  *out_height = height;
  return true;
}

uint64_t get_frame_generation(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return 0;
  return it->second->m_backend->frame_generation();
}

bool acquire_latest_frame(int view_id, const uint8_t **out_pixels,
                          int *out_width, int *out_height, int *out_pitch,
                          uint64_t *out_generation, void **out_frame_handle) {
  if (!out_pixels || !out_width || !out_height || !out_pitch ||
      !out_generation || !out_frame_handle)
    return false;

  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;

  FrameSnapshot snapshot;
  if (!it->second->m_backend->snapshot_frame(snapshot) || !snapshot.bitmap)
    return false;

  auto *frame = new (std::nothrow) LatestFrameHandle;
  if (!frame)
    return false;

  frame->bitmap = snapshot.bitmap;
  frame->width = snapshot.width;
  frame->height = snapshot.height;
  frame->pitch = snapshot.pitch;
  frame->generation = snapshot.generation;

  auto const *pixels = frame->bitmap->scanline_u8(0);
  if (!pixels) {
    delete frame;
    return false;
  }

  *out_pixels = pixels;
  *out_width = frame->width;
  *out_height = frame->height;
  *out_pitch = frame->pitch;
  *out_generation = frame->generation;
  *out_frame_handle = frame;
  return true;
}

void release_latest_frame(void *frame_handle) {
  if (!frame_handle)
    return;
  auto *frame = static_cast<LatestFrameHandle *>(frame_handle);
  delete frame;
}

bool acquire_latest_linux_dmabuf_frame(int view_id,
                                       LadybirdLinuxDmaBufFrame *out_frame) {
  if (!out_frame)
    return false;

  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;

  LinuxDmaBufFrameSnapshot snapshot;
  if (!it->second->m_backend->snapshot_linux_dmabuf_frame(snapshot))
    return false;

  out_frame->fd = snapshot.fd;
  out_frame->width = snapshot.width;
  out_frame->height = snapshot.height;
  out_frame->pitch = snapshot.pitch;
  out_frame->drm_format = snapshot.drm_format;
  out_frame->modifier = snapshot.modifier;
  out_frame->premultiplied = snapshot.premultiplied;
  out_frame->generation = snapshot.generation;
  return true;
}

void set_frame_callback(int view_id, FrameCallback callback, void *context) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_backend->callback_mutex);
    it->second->m_backend->frame_callback = callback;
    it->second->m_backend->frame_callback_context = context;
    std::fprintf(stderr,
                 "[Ladybird][engine] set_frame_callback view=%d callback=%p "
                 "context=%p\n",
                 view_id, reinterpret_cast<void *>(callback), context);
  }
}

void set_resize_callback(int view_id, ResizeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_backend->callback_mutex);
    it->second->m_backend->resize_callback = callback;
  }
}

void resize_window(int view_id, int width, int height) {
  if (width <= 0 || height <= 0)
    return;
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end())
    it->second->resize(width, height);
}

void navigate_to(int view_id, const char *url) {
  if (!url)
    return;
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    auto parsed = URL::Parser::basic_parse(AK::StringView(url, strlen(url)));
    if (parsed.has_value())
      it->second->load(parsed.value());
  }
}

void set_zoom(int view_id, double zoom) {
  if (zoom <= 0.0)
    return;
  std::fprintf(stderr, "[LibBird] set_zoom: view_id=%d, zoom=%f\n", view_id,
               zoom);
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->m_zoom = zoom;
    it->second->update_zoom_scale();
  }
}

void set_display_metadata(int view_id, bool has_display_id, uint64_t display_id,
                          double refresh_rate,
                          double maximum_frames_per_second) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  Optional<u64> optional_display_id;
  if (has_display_id)
    optional_display_id = display_id;

  std::fprintf(stderr,
               "[LibBird] set_display_metadata: view_id=%d has_display_id=%d "
               "display_id=%llu refresh_rate=%f max_fps=%f\n",
               view_id, has_display_id ? 1 : 0,
               static_cast<unsigned long long>(display_id), refresh_rate,
               maximum_frames_per_second);
  it->second->set_display_metadata(optional_display_id, refresh_rate,
                                   maximum_frames_per_second);
}

int get_iosurface_width(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return 0;
  return it->second->m_backend->width();
}

int get_iosurface_height(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return 0;
  return it->second->m_backend->height();
}

void set_url_change_callback(int view_id, UrlChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    ByteString current_url;
    bool has_valid_initial_url = false;
    {
      std::lock_guard lock(it->second->m_info_mutex);
      it->second->m_url_change_callback = callback;
      auto const &url = it->second->url();
      has_valid_initial_url = !url.scheme().is_empty();
      if (has_valid_initial_url)
        current_url = url.to_string().to_byte_string();
    }

    if (callback && has_valid_initial_url)
      callback(strdup(current_url.characters()));
  }
}

void set_title_change_callback(int view_id, TitleChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    ByteString current_title;
    {
      std::lock_guard lock(it->second->m_info_mutex);
      it->second->m_title_change_callback = callback;
      current_title = it->second->title().to_utf8().to_byte_string();
    }

    if (callback)
      callback(strdup(current_title.characters()));
  }
}

void set_favicon_change_callback(int view_id, FaviconChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_favicon_change_callback = callback;
  }
}

void set_cross_site_navigation_callback(int view_id,
                                        CrossSiteNavigationCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_cross_site_navigation_callback = callback;
  }
}

void reload_tab(int view_id) {
  // std::lock_guard<std::mutex> lock(g_web_views_mutex);
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->reload();
  }
}

void go_back(int view_id) {
  // std::lock_guard<std::mutex> lock(g_web_views_mutex);
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->traverse_the_history_by_delta(-1);
  }
}

void go_forward(int view_id) {
  // std::lock_guard<std::mutex> lock(g_web_views_mutex);
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->traverse_the_history_by_delta(1);
  }
}

bool can_go_back(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return it->second->navigate_back_action().enabled();
}

bool can_go_forward(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return it->second->navigate_forward_action().enabled();
}

char *get_view_url(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return nullptr;

  auto const &url = it->second->url();
  if (url.scheme().is_empty())
    return nullptr;

  auto bytes = url.to_string().to_byte_string();
  return strdup(bytes.characters());
}

char *get_bookmarks_json() {
  if (!s_app)
    return nullptr;

  auto json =
      WebView::Application::bookmark_store().serialize_items().serialized();
  auto bytes = json.to_byte_string();
  return strdup(bytes.characters());
}

void toggle_bookmark_for_view(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  auto &bookmark_store = WebView::Application::bookmark_store();
  auto const &url = it->second->url();

  if (auto bookmark = bookmark_store.find_bookmark_by_url(url);
      bookmark.has_value()) {
    bookmark_store.remove_item(bookmark->id);
    return;
  }

  bookmark_store.add_bookmark(url, it->second->title().to_utf8(),
                              it->second->favicon_base64_png());
}

bool is_current_view_bookmarked(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return WebView::Application::bookmark_store().is_bookmarked(
      it->second->url());
}

char *history_autocomplete_json(const char *query, int limit) {
  if (!s_app)
    return nullptr;

  String query_string;
  if (query && strlen(query) > 0) {
    auto maybe_query = String::from_utf8(StringView(query, strlen(query)));
    if (!maybe_query.is_error())
      query_string = maybe_query.release_value();
  }

  size_t safe_limit = limit > 0 ? static_cast<size_t>(limit) : 8;
  auto entries = WebView::Application::history_store().autocomplete_entries(
      query_string, safe_limit);

  JsonArray suggestions;
  suggestions.ensure_capacity(entries.size());

  for (auto const &entry : entries) {
    JsonObject item;
    item.set("url"sv, entry.url);
    if (entry.title.has_value())
      item.set("title"sv, *entry.title);
    if (entry.favicon_base64_png.has_value())
      item.set("favicon"sv, *entry.favicon_base64_png);
    suggestions.must_append(move(item));
  }

  auto json = JsonValue(move(suggestions)).serialized();
  auto bytes = json.to_byte_string();
  return strdup(bytes.characters());
}

void copy_selection(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  if (auto text = it->second->selected_text(); !text.is_empty()) {
    WebView::Application::the().insert_clipboard_entry(
        {std::move(text), "text/plain"_string});
  }
}

void paste_from_clipboard(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  it->second->paste_text_from_clipboard();
}

void set_loading_state_change_callback(int view_id,
                                       LoadingStateChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_loading_state_change_callback = callback;
    if (callback)
      callback(it->second->m_is_loading);
  }
}

void set_cursor_change_callback(int view_id, CursorChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_cursor_change_callback = callback;
  }
}

void set_context_menu_request_callback(int view_id,
                                       ContextMenuRequestCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end())
    it->second->set_context_menu_request_callback(callback);
}

void set_new_web_view_callback(int view_id, NewWebViewCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_new_web_view_callback = callback;
  }
}

bool activate_context_menu_action(int view_id, int action_token) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return it->second->activate_context_menu_action(action_token);
}

bool is_tab_loading(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return it->second->m_is_loading;
}

extern "C" {

void dispatch_mouse_event(int view_id, int type, int x, int y, int button,
                          int buttons, int modifiers, double wheel_delta_x,
                          double wheel_delta_y) {
  // std::lock_guard<std::mutex> lock(g_web_views_mutex);
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->dispatch_mouse_event(static_cast<Web::MouseEvent::Type>(type),
                                     x, y, button, buttons, modifiers,
                                     wheel_delta_x, wheel_delta_y);
  }
}

void dispatch_key_event(int view_id, int type, int keycode, int modifiers,
                        uint32_t code_point, bool repeat) {
  // std::lock_guard<std::mutex> lock(g_web_views_mutex);
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->dispatch_key_event(static_cast<Web::KeyEvent::Type>(type),
                                   keycode, modifiers, code_point, repeat);
  }
}
}

void set_ask_user_for_download_path_callback(
    AskUserForDownloadPathCallback callback) {
  g_ask_user_for_download_path_callback = callback;
}

void set_display_download_confirmation_dialog_callback(
    DisplayDownloadConfirmationDialogCallback callback) {
  g_display_download_confirmation_dialog_callback = callback;
}

void set_display_error_dialog_callback(DisplayErrorDialogCallback callback) {
  g_display_error_dialog_callback = callback;
}
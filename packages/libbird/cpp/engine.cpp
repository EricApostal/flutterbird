#include "engine.h"
#include "LibWebView/Application.h"
#include <cstdio>
#include <memory>
#include <mutex>
#include <print>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Platform-specific backend header.  All __APPLE__ ifdefs live here and
// in the on_ready_to_paint lambda — nowhere else in this file.
#ifdef __APPLE__
#include "platform/macos_view_backend.h"
#else
#include "platform/linux_view_backend.h"
#endif

#include <AK/BitCast.h>
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
#include <LibWebView/Utilities.h>
#include <LibWebView/ViewImplementation.h>
#include <string>

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

  // Mutex for the non-frame callbacks (URL, title, favicon).
  std::mutex m_info_mutex;

  UrlChangeCallback m_url_change_callback = nullptr;
  TitleChangeCallback m_title_change_callback = nullptr;
  FaviconChangeCallback m_favicon_change_callback = nullptr;

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

    Web::DevicePixelRect screen_rect{0, 0, 1920, 1080};
    client().async_update_screen_rects(m_client_state.page_index,
                                       {{screen_rect}}, 0);
  }

  virtual void initialize_client(
      CreateNewClient create_new_client = CreateNewClient::Yes) override {

    m_backend = create_view_backend();

    ViewImplementation::initialize_client(create_new_client);
    configure_client_process();
    set_system_visibility_state(Web::HTML::VisibilityState::Visible);

    // -----------------------------------------------------------------------
    // on_ready_to_paint — modelled after Qt's WebContentView pattern.
    //
    // Extract the Gfx::Bitmap from the front shared-image buffer and pass it
    // to the backend.  The backend stores it, detects size changes, and fires
    // the Flutter FrameCallback / ResizeCallback.
    //
    // macOS NOTE: SharedImageBuffer::iosurface_handle() gives the IOSurface
    // for zero-copy GPU texture upload.  Wire that into MacOSViewBackend once
    // on_iosurface_ready() is implemented; until then the bitmap CPU path
    // below works as a functional fallback on both platforms.
    // -----------------------------------------------------------------------
    on_ready_to_paint = [this]() {
      if (!m_client_state.has_usable_bitmap ||
          !m_client_state.front_bitmap.shared_image_buffer)
        return;
      auto bitmap = AK::RefPtr<Gfx::Bitmap const>(
          m_client_state.front_bitmap.shared_image_buffer->bitmap());
      m_backend->on_bitmap_ready(std::move(bitmap));
    };

    on_web_content_process_change_for_cross_site_navigation = [this]() {
      std::println("WebContent process changed for cross site navigation.");
      configure_client_process();
    };

    on_web_content_crashed = []() {
      std::println("WebContent process crashed.");
    };

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
  }

  void resize(int width, int height) {
    m_viewport_width = width;
    m_viewport_height = height;
    auto size = Web::DevicePixelSize{width, height};
    sync_device_pixel_ratio();
    client().async_set_viewport(m_client_state.page_index, size,
                                m_device_pixel_ratio, is_fullscreen());
    client().async_set_window_size(m_client_state.page_index, size);
  }

  void update_zoom_scale() {
    sync_device_pixel_ratio();
    client().async_set_viewport(m_client_state.page_index, viewport_size(),
                                m_device_pixel_ratio, is_fullscreen());
  }

  void dispatch_mouse_event(Web::MouseEvent::Type type, int x, int y,
                            int button, int buttons, int modifiers,
                            int wheel_delta_x, int wheel_delta_y) {
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
                      code_point, repeat, nullptr});
  }

  virtual ~FlutterViewImpl() = default;

private:
  explicit FlutterViewImpl(int view_id) : m_view_id(view_id) {}

  virtual void update_zoom() override {}

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

  virtual NonnullOwnPtr<Core::EventLoop> create_platform_event_loop() override {
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

  virtual Utf16String clipboard_text() const override {
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
    std::println("Failed to construct Ladybird Engine Application");
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
        std::println("Opening in existing process");
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

void set_frame_callback(int view_id, FrameCallback callback, void *context) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_backend->callback_mutex);
    it->second->m_backend->frame_callback = callback;
    it->second->m_backend->frame_callback_context = context;
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
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->m_zoom = zoom;
    it->second->update_zoom_scale();
  }
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
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_url_change_callback = callback;
  }
}

void set_title_change_callback(int view_id, TitleChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_title_change_callback = callback;
  }
}

void set_favicon_change_callback(int view_id, FaviconChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_favicon_change_callback = callback;
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

bool can_go_back(int view_id) { return true; }

bool can_go_forward(int view_id) { return true; }

extern "C" {

void dispatch_mouse_event(int view_id, int type, int x, int y, int button,
                          int buttons, int modifiers, int wheel_delta_x,
                          int wheel_delta_y) {
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

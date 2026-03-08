#include "LibWebView/Application.h"
#include "engine.h"
#include <print>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <mutex>

#ifdef __APPLE__
#include <CoreVideo/CoreVideo.h>
#include <CoreFoundation/CoreFoundation.h>
#endif

#include <AK/OwnPtr.h>
#include <AK/StringView.h>
#include <LibCore/EventLoop.h>
#include <LibGfx/Bitmap.h>
#include <LibWebView/BrowserProcess.h>
#include <LibWebView/ViewImplementation.h>
#include <LibURL/URL.h>
#include <LibMain/Main.h>
#include <LibURL/Parser.h>
#include <AK/LexicalPath.h>
#include <LibGfx/SystemTheme.h>
#include <LibWeb/PixelUnits.h>
#include <LibWebView/Utilities.h>
#include <LibCore/System.h>
#include <LibWeb/Page/InputEvent.h>
#include <string>

std::mutex g_web_views_mutex;
int g_next_view_id = 1;
int g_active_view_id = -1;

class FlutterViewImpl final : public WebView::ViewImplementation
{
public:
    static ErrorOr<NonnullOwnPtr<FlutterViewImpl>> create(int view_id)
    {
        return adopt_nonnull_own_or_enomem(new (std::nothrow) FlutterViewImpl(view_id));
    }

    int m_view_id;

#ifdef __APPLE__
    CVPixelBufferRef m_pixel_buffer = nullptr;
#else
    AK::RefPtr<Gfx::Bitmap const> m_bitmap = nullptr;
#endif
    int m_width = 800;
    int m_height = 600;
    double m_zoom = 2;

    FrameCallback m_frame_callback = nullptr;
    void *m_frame_callback_context = nullptr;

    ResizeCallback m_resize_callback = nullptr;

    UrlChangeCallback m_url_change_callback = nullptr;
    TitleChangeCallback m_title_change_callback = nullptr;
    FaviconChangeCallback m_favicon_change_callback = nullptr;

    std::mutex m_mutex;

    void configure_client_process()
    {
        auto theme_path = LexicalPath::join(WebView::s_ladybird_resource_root, "themes"sv, "Default.ini"sv);
        auto theme = Gfx::load_system_theme(theme_path.string()).release_value_but_fixme_should_propagate_errors();

        client().async_update_system_theme(m_client_state.page_index, theme);
        client().async_set_viewport(m_client_state.page_index, viewport_size(), m_zoom);
        client().async_set_window_size(m_client_state.page_index, viewport_size());

        Web::DevicePixelRect screen_rect{0, 0, 1920, 1080};
        client().async_update_screen_rects(m_client_state.page_index, {{screen_rect}}, 0);
    }

    virtual void initialize_client(CreateNewClient create_new_client = CreateNewClient::Yes) override
    {
        ViewImplementation::initialize_client(create_new_client);

        configure_client_process();

        set_system_visibility_state(Web::HTML::VisibilityState::Visible);

        on_ready_to_paint = [this]()
        {
#ifdef __APPLE__
            if (m_client_state.has_usable_bitmap && m_client_state.front_bitmap.iosurface_ref)
            {
                auto size = m_client_state.front_bitmap.last_painted_size.to_type<int>();

                IOSurfaceRef iosurface = (IOSurfaceRef)m_client_state.front_bitmap.iosurface_ref;

                std::lock_guard<std::mutex> lock(m_mutex);

                bool size_changed = (size.width() != m_width || size.height() != m_height);
                m_width = size.width();
                m_height = size.height();

                if (m_pixel_buffer)
                {
                    CVPixelBufferRelease(m_pixel_buffer);
                    m_pixel_buffer = nullptr;
                }

                CVReturn result = CVPixelBufferCreateWithIOSurface(
                    kCFAllocatorDefault,
                    iosurface,
                    nullptr,
                    &m_pixel_buffer);

                if (result != kCVReturnSuccess)
                {
                    std::println("Failed to wrap IOSurface in CVPixelBuffer! Error: {}", result);
                    return;
                }

                if (size_changed && m_resize_callback)
                {
                    m_resize_callback();
                }

                if (m_frame_callback)
                {
                    m_frame_callback(m_frame_callback_context);
                }
            }
#else
            if (m_client_state.has_usable_bitmap)
            {
                // Linux implementation using localized Gfx::Bitmap directly from m_client_state
                auto bitmap = m_client_state.front_bitmap.bitmap;
                if (bitmap)
                {
                    std::lock_guard<std::mutex> lock(m_mutex);
                    m_bitmap = bitmap;

                    bool size_changed = (m_bitmap->width() != m_width || m_bitmap->height() != m_height);
                    m_width = m_bitmap->width();
                    m_height = m_bitmap->height();

                    if (size_changed && m_resize_callback)
                    {
                        m_resize_callback();
                    }

                    if (m_frame_callback)
                    {
                        m_frame_callback(m_frame_callback_context);
                    }
                }
            }
#endif
        };

        on_web_content_process_change_for_cross_site_navigation = [this]()
        {
            std::println("WebContent process changed for cross site navigation!");
            configure_client_process();
        };

        on_web_content_crashed = []()
        {
            std::println("WebContent process crashed!!!");
        };

        on_url_change = [this](URL::URL const &url)
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (m_url_change_callback)
            {
                auto url_string = url.to_string().to_byte_string();
                m_url_change_callback(strdup(url_string.characters()));
            }
        };

        on_title_change = [this](Utf16String const &title)
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (m_title_change_callback)
            {
                auto title_string = title.to_utf8().to_byte_string();
                m_title_change_callback(strdup(title_string.characters()));
            }
        };

        on_favicon_change = [this](Gfx::Bitmap const &bitmap)
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (m_favicon_change_callback)
            {
                size_t length = bitmap.width() * bitmap.height() * 4;
                uint8_t *buffer = (uint8_t *)malloc(length);
                memcpy(buffer, reinterpret_cast<const uint8_t *>(bitmap.begin()), length);
                m_favicon_change_callback(buffer, bitmap.width(), bitmap.height());
            }
        };
    }

    void resize(int width, int height)
    {
        auto size = Web::DevicePixelSize{width, height};
        client().async_set_viewport(m_client_state.page_index, size, m_zoom);
        client().async_set_window_size(m_client_state.page_index, size);
    }

    void update_zoom_scale()
    {
        auto size = Web::DevicePixelSize{m_width, m_height};
        client().async_set_viewport(m_client_state.page_index, size, m_zoom);
    }

    void dispatch_mouse_event(Web::MouseEvent::Type type, int x, int y, int button, int buttons, int modifiers, int wheel_delta_x, int wheel_delta_y)
    {
        Web::DevicePixelPoint position = {x, y};
        Web::DevicePixelPoint screen_position = {x, y};
        enqueue_input_event(Web::MouseEvent{type, position, screen_position, static_cast<Web::UIEvents::MouseButton>(button), static_cast<Web::UIEvents::MouseButton>(buttons), static_cast<Web::UIEvents::KeyModifier>(modifiers), wheel_delta_x, wheel_delta_y, nullptr});
    }

    void dispatch_key_event(Web::KeyEvent::Type type, int keycode, int modifiers, uint32_t code_point, bool repeat)
    {
        enqueue_input_event(Web::KeyEvent{type, static_cast<Web::UIEvents::KeyCode>(keycode), static_cast<Web::UIEvents::KeyModifier>(modifiers), code_point, repeat, nullptr});
    }

    virtual ~FlutterViewImpl()
    {
#ifdef __APPLE__
        if (m_pixel_buffer)
        {
            CVPixelBufferRelease(m_pixel_buffer);
        }
#endif
    }

private:
    FlutterViewImpl(int view_id) : m_view_id(view_id) {}

    virtual void update_zoom() override {}
    virtual Web::DevicePixelSize viewport_size() const override { return {m_width, m_height}; }
    virtual Gfx::IntPoint to_content_position(Gfx::IntPoint widget_position) const override { return widget_position; }
    virtual Gfx::IntPoint to_widget_position(Gfx::IntPoint content_position) const override { return content_position; }
};

#include <map>
std::map<int, AK::OwnPtr<FlutterViewImpl>> g_web_views;

class FlutterApplication : public WebView::Application
{
    WEB_VIEW_APPLICATION(FlutterApplication)

public:
    FlutterApplication() = default;
    virtual ~FlutterApplication() override = default;

    virtual void create_platform_arguments(Core::ArgsParser &) override {}
    virtual void create_platform_options(WebView::BrowserOptions &, WebView::RequestServerOptions &, WebView::WebContentOptions &) override {}

    virtual bool should_capture_web_content_output() const override { return false; }

    virtual NonnullOwnPtr<Core::EventLoop> create_platform_event_loop() override
    {
        return WebView::Application::create_platform_event_loop();
    }

    virtual Optional<WebView::ViewImplementation &> active_web_view() const override
    {
        std::lock_guard<std::mutex> lock(g_web_views_mutex);
        if (g_active_view_id != -1)
        {
            auto it = g_web_views.find(g_active_view_id);
            if (it != g_web_views.end())
                return *it->second;
        }
        if (!g_web_views.empty())
        {
            return *g_web_views.begin()->second;
        }
        return {};
    }

    virtual Optional<WebView::ViewImplementation &> open_blank_new_tab(Web::HTML::ActivateTab) const override
    {
        return {};
    }
    virtual Optional<ByteString> ask_user_for_download_path(StringView) const override { return {}; }
    virtual void display_download_confirmation_dialog(StringView, LexicalPath const &) const override {}
    virtual void display_error_dialog(StringView) const override {}

    virtual Utf16String clipboard_text() const override { return WebView::Application::clipboard_text(); }
    virtual Vector<Web::Clipboard::SystemClipboardRepresentation> clipboard_entries() const override { return WebView::Application::clipboard_entries(); }
    virtual void insert_clipboard_entry(Web::Clipboard::SystemClipboardRepresentation entry) override
    {
        WebView::Application::insert_clipboard_entry(std::move(entry));
    }
};

static AK::OwnPtr<FlutterApplication> s_app;
static AK::OwnPtr<WebView::BrowserProcess> s_browser_process;

void init_ladybird()
{
    static bool initialized = false;
    if (initialized)
        return;

    initialized = true;

    AK::set_rich_debug_enabled(true);

#ifdef __APPLE__
    WebView::platform_init();
#else
    if (auto current_executable_path = Core::System::current_executable_path(); !current_executable_path.is_error())
    {
        auto parent_path = LexicalPath::dirname(current_executable_path.value());
        auto lib_path = LexicalPath::join(parent_path, "lib"sv).string();
        WebView::platform_init(lib_path);
    }
#endif

    static char const *argv[] = {"Ladybird", nullptr};

    // TODO: I don't really know what this means?
    static AK::StringView string_views[] = {AK::StringView("Ladybird", 8)};
    Main::Arguments arguments = {1, (char **)argv, {string_views, 1}};

    auto app = FlutterApplication::create(arguments);
    if (app.is_error())
    {
        std::println("Failed to construct Ladybird Engine Application");
        return;
    }
    s_app = app.release_value();

    s_browser_process = make<WebView::BrowserProcess>();

    if (auto const &browser_options = WebView::Application::browser_options();
        !browser_options.headless_mode.has_value())
    {
        if (browser_options.force_new_process == WebView::ForceNewProcess::No)
        {
            auto disposition = s_browser_process->connect(browser_options.raw_urls,
                                                          browser_options.new_window);

            if (!disposition.is_error() &&
                disposition.value() == WebView::BrowserProcess::ProcessDisposition::ExitProcess)
            {
                std::println("Opening in existing process");
                return;
            }
        }
    }
}

extern "C" void tick_ladybird()
{
    if (Core::EventLoop::is_running())
    {
        Core::EventLoop::current().pump(Core::EventLoop::WaitMode::PollForEvents);
    }
}

int create_web_view()
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    int id = g_next_view_id++;
    auto view = FlutterViewImpl::create(id).release_value();
    view->initialize_client();
    g_web_views[id] = std::move(view);

    if (g_active_view_id == -1)
    {
        g_active_view_id = id;
    }
    return id;
}

void destroy_web_view(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    if (g_active_view_id == view_id)
    {
        g_active_view_id = -1;
    }
    g_web_views.erase(view_id);
}

void *get_latest_pixel_buffer(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it == g_web_views.end())
        return nullptr;

    std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
#ifdef __APPLE__
    if (!it->second->m_pixel_buffer)
        return nullptr;

    CVPixelBufferRetain(it->second->m_pixel_buffer);
    return it->second->m_pixel_buffer;
#else
    if (!it->second->m_bitmap)
        return nullptr;
    // Return pointer to the raw pixel data
    // Assuming ARGB format which Flutter expects
    // We return the raw data pointer from Gfx::Bitmap
    return const_cast<u8 *>(it->second->m_bitmap->scanline_u8(0));
#endif
}

void set_frame_callback(int view_id, FrameCallback callback, void *context)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
        it->second->m_frame_callback = callback;
        it->second->m_frame_callback_context = context;
    }
}

void set_resize_callback(int view_id, ResizeCallback callback)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
        it->second->m_resize_callback = callback;
    }
}

void resize_window(int view_id, int width, int height)
{
    if (width <= 0 || height <= 0)
        return;
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        it->second->resize(width, height);
    }
}

void navigate_to(int view_id, const char *url)
{
    if (!url)
        return;
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        auto parsed = URL::Parser::basic_parse(AK::StringView(url, strlen(url)));
        if (parsed.has_value())
        {
            it->second->load(parsed.value());
        }
    }
}

void set_zoom(int view_id, double zoom)
{
    if (zoom <= 0.0)
        return;
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        it->second->m_zoom = zoom;
        it->second->update_zoom_scale();
    }
}

int get_iosurface_width(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it == g_web_views.end())
        return 0;

    std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
#ifdef __APPLE__
    if (!it->second->m_pixel_buffer)
        return it->second->m_width;
    IOSurfaceRef iosurface = CVPixelBufferGetIOSurface(it->second->m_pixel_buffer);
    if (!iosurface)
        return it->second->m_width;
    return IOSurfaceGetWidth(iosurface);
#else
    if (it->second->m_bitmap)
        return it->second->m_bitmap->width();
    return it->second->m_width;
#endif
}

int get_iosurface_height(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it == g_web_views.end())
        return 0;

    std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
#ifdef __APPLE__
    if (!it->second->m_pixel_buffer)
        return it->second->m_height;
    IOSurfaceRef iosurface = CVPixelBufferGetIOSurface(it->second->m_pixel_buffer);
    if (!iosurface)
        return it->second->m_height;
    return IOSurfaceGetHeight(iosurface);
#else
    if (it->second->m_bitmap)
        return it->second->m_bitmap->height();
    return it->second->m_height;
#endif
}

void set_url_change_callback(int view_id, UrlChangeCallback callback)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
        it->second->m_url_change_callback = callback;
    }
}

void set_title_change_callback(int view_id, TitleChangeCallback callback)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
        it->second->m_title_change_callback = callback;
    }
}

void set_favicon_change_callback(int view_id, FaviconChangeCallback callback)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
        it->second->m_favicon_change_callback = callback;
    }
}

void reload_tab(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        it->second->reload();
    }
}

void go_back(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        it->second->traverse_the_history_by_delta(-1);
    }
}

void go_forward(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        it->second->traverse_the_history_by_delta(1);
    }
}

bool can_go_back(int view_id)
{
    return true;
}

bool can_go_forward(int view_id)
{
    return true;
}

extern "C"
{

    void dispatch_mouse_event(int view_id, int type, int x, int y, int button, int buttons, int modifiers, int wheel_delta_x, int wheel_delta_y)
    {
        std::lock_guard<std::mutex> lock(g_web_views_mutex);
        auto it = g_web_views.find(view_id);
        if (it != g_web_views.end())
        {
            it->second->dispatch_mouse_event(static_cast<Web::MouseEvent::Type>(type), x, y, button, buttons, modifiers, wheel_delta_x, wheel_delta_y);
        }
    }

    void dispatch_key_event(int view_id, int type, int keycode, int modifiers, uint32_t code_point, bool repeat)
    {
        std::lock_guard<std::mutex> lock(g_web_views_mutex);
        auto it = g_web_views.find(view_id);
        if (it != g_web_views.end())
        {
            it->second->dispatch_key_event(static_cast<Web::KeyEvent::Type>(type), keycode, modifiers, code_point, repeat);
        }
    }
}

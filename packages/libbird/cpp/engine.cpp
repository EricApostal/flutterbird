#include "LibWebView/Application.h"
#include "engine.h"
#include <print>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <mutex>
#include <CoreVideo/CoreVideo.h>
#include <CoreFoundation/CoreFoundation.h>

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

std::mutex g_frame_mutex;
CVPixelBufferRef g_pixel_buffer = nullptr;
int g_width = 800;
int g_height = 600;
double g_zoom = 1.5;

FrameCallback g_frame_callback = nullptr;
void* g_frame_callback_context = nullptr;

ResizeCallback g_resize_callback = nullptr;

class FlutterViewImpl final : public WebView::ViewImplementation {
public:
    static ErrorOr<NonnullOwnPtr<FlutterViewImpl>> create() {
        return adopt_nonnull_own_or_enomem(new (std::nothrow) FlutterViewImpl());
    }

    virtual void initialize_client(CreateNewClient create_new_client = CreateNewClient::Yes) override {
        ViewImplementation::initialize_client(create_new_client);

        auto theme_path = LexicalPath::join(WebView::s_ladybird_resource_root, "themes"sv, "Default.ini"sv);
        auto theme = Gfx::load_system_theme(theme_path.string()).release_value_but_fixme_should_propagate_errors();

        client().async_update_system_theme(m_client_state.page_index, theme);
        client().async_set_viewport(m_client_state.page_index, viewport_size(), g_zoom);
        client().async_set_window_size(m_client_state.page_index, viewport_size());
        
        Web::DevicePixelRect screen_rect { 0, 0, 1920, 1080 };
        client().async_update_screen_rects(m_client_state.page_index, { { screen_rect } }, 0);
        
        set_system_visibility_state(Web::HTML::VisibilityState::Visible);

        on_ready_to_paint = [this]() {
            // Ensure we have a valid front bitmap and an IOSurface reference
            if (m_client_state.has_usable_bitmap && m_client_state.front_bitmap.iosurface_ref) {
                auto size = m_client_state.front_bitmap.last_painted_size.to_type<int>();
                
                // Cast the void* from Ladybird back to an Apple IOSurfaceRef
                IOSurfaceRef iosurface = (IOSurfaceRef)m_client_state.front_bitmap.iosurface_ref;

                IOSurfaceRef current_iosurface = g_pixel_buffer ? CVPixelBufferGetIOSurface(g_pixel_buffer) : nullptr;

                std::lock_guard<std::mutex> lock(g_frame_mutex);
                
                // If the size changed or iosurface changed, we need to wrap the new IOSurface
                if (current_iosurface != iosurface || size.width() != g_width || size.height() != g_height || !g_pixel_buffer) {
                    bool size_changed = (size.width() != g_width || size.height() != g_height);
                    
                    g_width = size.width();
                    g_height = size.height();
                    
                    if (g_pixel_buffer) {
                        CVPixelBufferRelease(g_pixel_buffer);
                        g_pixel_buffer = nullptr;
                    }

                    // Map the IOSurface natively without properties to avoid metal texture cache corruption on resize
                    CVReturn result = CVPixelBufferCreateWithIOSurface(
                        kCFAllocatorDefault,
                        iosurface,
                        nullptr,
                        &g_pixel_buffer
                    );

                    if (result != kCVReturnSuccess) {
                        std::println("Failed to wrap IOSurface in CVPixelBuffer! Error: {}", result);
                        return;
                    }

                    if (size_changed && g_resize_callback) {
                        g_resize_callback();
                    }
                }

                if (g_frame_callback) {
                    g_frame_callback(g_frame_callback_context);
                }
            }
        };
        on_web_content_process_change_for_cross_site_navigation = []() {
            std::println("WebContent process changed for cross site navigation!");
        };

        on_web_content_crashed = []() {
            std::println("WebContent process crashed!!!");
        };
        
    }

    void resize(int width, int height) {
        auto size = Web::DevicePixelSize { width, height };
        client().async_set_viewport(m_client_state.page_index, size, g_zoom);
        client().async_set_window_size(m_client_state.page_index, size);
    }

    void update_zoom_scale() {
        auto size = Web::DevicePixelSize { g_width, g_height };
        client().async_set_viewport(m_client_state.page_index, size, g_zoom);
    }

    void dispatch_mouse_event(Web::MouseEvent::Type type, int x, int y, int button, int buttons, int modifiers, int wheel_delta_x, int wheel_delta_y) {
        Web::DevicePixelPoint position = { x, y };
        Web::DevicePixelPoint screen_position = { x, y };
        enqueue_input_event(Web::MouseEvent { type, position, screen_position, static_cast<Web::UIEvents::MouseButton>(button), static_cast<Web::UIEvents::MouseButton>(buttons), static_cast<Web::UIEvents::KeyModifier>(modifiers), wheel_delta_x, wheel_delta_y, nullptr });
    }

    void dispatch_key_event(Web::KeyEvent::Type type, int keycode, int modifiers, uint32_t code_point, bool repeat) {
        enqueue_input_event(Web::KeyEvent { type, static_cast<Web::UIEvents::KeyCode>(keycode), static_cast<Web::UIEvents::KeyModifier>(modifiers), code_point, repeat, nullptr });
    }

private:
    FlutterViewImpl() {}

    virtual void update_zoom() override {}
    virtual Web::DevicePixelSize viewport_size() const override { return { g_width, g_height }; }
    virtual Gfx::IntPoint to_content_position(Gfx::IntPoint widget_position) const override { return widget_position; }
    virtual Gfx::IntPoint to_widget_position(Gfx::IntPoint content_position) const override { return content_position; }
};

AK::OwnPtr<FlutterViewImpl> g_web_view;

class FlutterApplication : public WebView::Application {
    WEB_VIEW_APPLICATION(FlutterApplication)

public:

    FlutterApplication() = default;
    virtual ~FlutterApplication() override = default;

    virtual void create_platform_arguments(Core::ArgsParser&) override {}
    virtual void create_platform_options(WebView::BrowserOptions&, WebView::RequestServerOptions&, WebView::WebContentOptions&) override {}
    
    virtual bool should_capture_web_content_output() const override { return false; }

    virtual NonnullOwnPtr<Core::EventLoop> create_platform_event_loop() override {
        return WebView::Application::create_platform_event_loop();
    }

    virtual Optional<WebView::ViewImplementation&> active_web_view() const override { 
        if (g_web_view) return *g_web_view;
        return {}; 
    }
    
    virtual Optional<WebView::ViewImplementation&> open_blank_new_tab(Web::HTML::ActivateTab) const override { return {}; }
    virtual Optional<ByteString> ask_user_for_download_path(StringView) const override { return {}; }
    virtual void display_download_confirmation_dialog(StringView, LexicalPath const&) const override {}
    virtual void display_error_dialog(StringView) const override {}
    
    virtual Utf16String clipboard_text() const override { return WebView::Application::clipboard_text(); }
    virtual Vector<Web::Clipboard::SystemClipboardRepresentation> clipboard_entries() const override { return WebView::Application::clipboard_entries(); }
    virtual void insert_clipboard_entry(Web::Clipboard::SystemClipboardRepresentation entry) override {
        WebView::Application::insert_clipboard_entry(std::move(entry));
    }
};

static AK::OwnPtr<FlutterApplication> s_app;
static AK::OwnPtr<WebView::BrowserProcess> s_browser_process;

void init_ladybird() {
    static bool initialized = false;
    if (initialized)
        return;

    AK::set_rich_debug_enabled(true);

    static char const* argv[] = {"Ladybird", nullptr};

    // TODO: I don't really know what this means?
    static AK::StringView string_views[] = {AK::StringView("Ladybird", 8)};
    Main::Arguments arguments = {1, (char**)argv, {string_views, 1}};

    auto app = FlutterApplication::create(arguments);
    if (app.is_error()) {
        std::println("Failed to construct Ladybird Engine Application");
        return;
    }
    s_app = app.release_value();
    

    s_browser_process = make<WebView::BrowserProcess>();
    
    if (auto const& browser_options = WebView::Application::browser_options();
        !browser_options.headless_mode.has_value()) {
        if (browser_options.force_new_process == WebView::ForceNewProcess::No) {
            auto disposition = s_browser_process->connect(browser_options.raw_urls,
                                                          browser_options.new_window);

            if (!disposition.is_error() &&
                disposition.value() == WebView::BrowserProcess::ProcessDisposition::ExitProcess) {
                std::println("Opening in existing process");
                return;
            }
        }
    }

    auto exe = Core::System::current_executable_path();
    if (!exe.is_error()) {
        // std::println("Executable path: {}", exe.value().view());
    } else {
        std::println("Could not get executable path!");
    }
    // std::println("Resource root: {}", WebView::s_ladybird_resource_root.view());

    g_web_view = FlutterViewImpl::create().release_value();
    g_web_view->initialize_client();

    const char* url = "https://ladybird.org";
    g_web_view->load(URL::Parser::basic_parse(AK::StringView(url, strlen(url))).value());

    initialized = true;
}

extern "C" void tick_ladybird() {
    if (Core::EventLoop::is_running()) {
        Core::EventLoop::current().pump(Core::EventLoop::WaitMode::PollForEvents);
    }
}

void* get_latest_pixel_buffer() {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    if (!g_pixel_buffer) {
        return nullptr;
    }

    CVPixelBufferRetain(g_pixel_buffer);
    return g_pixel_buffer;
}

void set_frame_callback(FrameCallback callback, void* context) {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    g_frame_callback = callback;
    g_frame_callback_context = context;
}

void set_resize_callback(ResizeCallback callback) {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    g_resize_callback = callback;
}

void resize_window(int width, int height) {
    if (!g_web_view || width <= 0 || height <= 0) {
        return;
    }

    g_web_view->resize(width, height);
}

void navigate_to(const char* url) {
    if (!g_web_view || !url) return;
    auto parsed = URL::Parser::basic_parse(AK::StringView(url, strlen(url)));
    if (parsed.has_value()) {
        g_web_view->load(parsed.value());
    }
}

void set_zoom(double zoom) {
    if (zoom <= 0.0) return;
    g_zoom = zoom;
    if (g_web_view) {
        g_web_view->update_zoom_scale();
    }
}

int get_iosurface_width() {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    if (!g_pixel_buffer) return g_width;
    IOSurfaceRef iosurface = CVPixelBufferGetIOSurface(g_pixel_buffer);
    if (!iosurface) return g_width;
    return IOSurfaceGetWidth(iosurface);
}

int get_iosurface_height() {
    std::lock_guard<std::mutex> lock(g_frame_mutex);
    if (!g_pixel_buffer) return g_height;
    IOSurfaceRef iosurface = CVPixelBufferGetIOSurface(g_pixel_buffer);
    if (!iosurface) return g_height;
    return IOSurfaceGetHeight(iosurface);
}

extern "C" {

void dispatch_mouse_event(int type, int x, int y, int button, int buttons, int modifiers, int wheel_delta_x, int wheel_delta_y) {
    if (g_web_view) {
        g_web_view->dispatch_mouse_event(static_cast<Web::MouseEvent::Type>(type), x, y, button, buttons, modifiers, wheel_delta_x, wheel_delta_y);
    }
}

void dispatch_key_event(int type, int keycode, int modifiers, uint32_t code_point, bool repeat) {
    if (g_web_view) {
        g_web_view->dispatch_key_event(static_cast<Web::KeyEvent::Type>(type), keycode, modifiers, code_point, repeat);
    }
}

}


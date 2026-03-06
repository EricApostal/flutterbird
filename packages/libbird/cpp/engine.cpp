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

std::mutex g_frame_mutex;
CVPixelBufferRef g_pixel_buffer = nullptr;
int g_width = 800;
int g_height = 600;
double g_zoom = 1.5;

FrameCallback g_frame_callback = nullptr;
void* g_frame_callback_context = nullptr;

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
                    g_width = size.width();
                    g_height = size.height();
                    
                    if (g_pixel_buffer) {
                        CVPixelBufferRelease(g_pixel_buffer);
                        g_pixel_buffer = nullptr;
                    }

                    int width = g_width;
                    int height = g_height;
                    size_t surf_width = IOSurfaceGetWidth(iosurface);
                    size_t surf_height = IOSurfaceGetHeight(iosurface);

                    int right_pad = (surf_width > static_cast<size_t>(width)) ? (surf_width - width) : 0;
                    int bottom_pad = (surf_height > static_cast<size_t>(height)) ? (surf_height - height) : 0;
                    int32_t format = IOSurfaceGetPixelFormat(iosurface);

                    CFNumberRef widthRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &width);
                    CFNumberRef heightRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &height);
                    CFNumberRef rightPadRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &right_pad);
                    CFNumberRef bottomPadRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bottom_pad);
                    CFNumberRef formatRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &format);

                    const void* keys[] = { 
                        kCVPixelBufferWidthKey, 
                        kCVPixelBufferHeightKey, 
                        kCVPixelBufferExtendedPixelsRightKey, 
                        kCVPixelBufferExtendedPixelsBottomKey,
                        kCVPixelBufferPixelFormatTypeKey 
                    };
                    const void* values[] = { widthRef, heightRef, rightPadRef, bottomPadRef, formatRef };

                    CFDictionaryRef attributes = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 5, 
                                                                    &kCFTypeDictionaryKeyCallBacks, 
                                                                    &kCFTypeDictionaryValueCallBacks);

                    // Map the IOSurface using exact properties and padded borders
                    CVReturn result = CVPixelBufferCreateWithIOSurface(
                        kCFAllocatorDefault,
                        iosurface,
                        attributes,
                        &g_pixel_buffer
                    );

                    CFRelease(attributes);
                    CFRelease(widthRef);
                    CFRelease(heightRef);
                    CFRelease(rightPadRef);
                    CFRelease(bottomPadRef);
                    CFRelease(formatRef);
                    
                    if (result != kCVReturnSuccess) {
                        std::println("Failed to wrap IOSurface in CVPixelBuffer! Error: {}", result);
                        return;
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
    // g_web_view->load(URL::Parser::basic_parse(AK::StringView("https://giphy.com", 17)).value());
    const char* url = "https://reddit.com";
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
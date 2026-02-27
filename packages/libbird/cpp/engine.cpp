#include "LibWebView/Application.h"
#include <print>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <thread>
#include <mutex>

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
uint8_t* g_latest_frame = nullptr;
int g_width = 800;
int g_height = 600;

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
        client().async_set_viewport(m_client_state.page_index, viewport_size(), 1.0);
        client().async_set_window_size(m_client_state.page_index, viewport_size());
        
        Web::DevicePixelRect screen_rect { 0, 0, 1920, 1080 }; // Dummy screen rect for now
        client().async_update_screen_rects(m_client_state.page_index, { { screen_rect } }, 0);
        
        set_system_visibility_state(Web::HTML::VisibilityState::Visible);

        on_ready_to_paint = [this]() {
            if (m_client_state.has_usable_bitmap && m_client_state.front_bitmap.bitmap) {
                auto const* bitmap = m_client_state.front_bitmap.bitmap.ptr();
                auto size = m_client_state.front_bitmap.last_painted_size.to_type<int>();
                
                std::lock_guard<std::mutex> lock(g_frame_mutex);
                
                if (size.width() != g_width || size.height() != g_height || !g_latest_frame) {
                    g_width = size.width();
                    g_height = size.height();
                    delete[] g_latest_frame;
                    g_latest_frame = new uint8_t[g_width * g_height * 4];
                }

                memcpy(g_latest_frame, bitmap->scanline(0), g_width * g_height * 4);
            }
        };

        on_web_content_process_change_for_cross_site_navigation = []() {
            std::println("WebContent process changed for cross site navigation!");
        };

        on_web_content_crashed = []() {
            std::println("WebContent process crashed!!!");
        };
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
    
    virtual bool should_capture_web_content_output() const override { return true; }

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

#include "engine.h"

static AK::OwnPtr<FlutterApplication> s_app;
static AK::OwnPtr<WebView::BrowserProcess> s_browser_process;

void init_ladybird() {
    std::println("YOOO we out here");
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
    
    std::println("doing options");
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
    std::println("end options");

    auto exe = Core::System::current_executable_path();
    if (!exe.is_error()) {
        std::println("Executable path: {}", exe.value().view());
    } else {
        std::println("Could not get executable path!");
    }
    std::println("Resource root: {}", WebView::s_ladybird_resource_root.view());

    g_web_view = FlutterViewImpl::create().release_value();
    g_web_view->initialize_client();
    g_web_view->load(URL::Parser::basic_parse(AK::StringView("https://ladybird.org", 20)).value());
    std::println("loaded webview!");
    initialized = true;
}

uint8_t* get_latest_frame(int* out_width, int* out_height) {
    if (Core::EventLoop::is_running()) {
        Core::EventLoop::current().pump(Core::EventLoop::WaitMode::PollForEvents);
    }

    std::lock_guard<std::mutex> lock(g_frame_mutex);
    if (!g_latest_frame) {
        return nullptr;
    }

    *out_width = g_width;
    *out_height = g_height;
    
    int size = g_width * g_height * 4;
    uint8_t* buffer_copy = (uint8_t*)malloc(size);
    memcpy(buffer_copy, g_latest_frame, size);
    
    return buffer_copy;
}

void free_frame(uint8_t* buffer) {
    free(buffer);
}
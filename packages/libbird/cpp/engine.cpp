#include "LibWebView/Application.h"
#include "engine.h"
#include <print>
#include <cstdio>
#include <cerrno>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <mutex>
#include <vector>
#include <chrono>
#include <sys/stat.h>

#ifdef __APPLE__
#include <CoreVideo/CoreVideo.h>
#include <CoreFoundation/CoreFoundation.h>
#elif defined(__ANDROID__)
#include <android/log.h>
#include <jni.h>
#endif

#include <AK/OwnPtr.h>
#include <AK/StringView.h>
#include <LibCore/EventLoop.h>
#include <LibCore/Socket.h>
#include <LibGfx/Bitmap.h>
#include <LibWeb/Crypto/Crypto.h>
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
#include <LibCore/ResourceImplementationFile.h>
#include <LibCore/ResourceImplementation.h>
#include <LibWeb/Page/InputEvent.h>
#include <string>

#if defined(__ANDROID__)
#define LADYBIRD_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "LadybirdEngine", __VA_ARGS__)
#define LADYBIRD_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "LadybirdEngine", __VA_ARGS__)

static JavaVM* s_java_vm = nullptr;
static jobject s_plugin_instance = nullptr;
static jmethodID s_bind_webcontent_service_method = nullptr;

extern "C" LADYBIRD_API void register_android_plugin_instance(JNIEnv* env, jobject plugin)
{
    if (!env || !plugin)
        return;

    if (s_plugin_instance)
        env->DeleteGlobalRef(s_plugin_instance);

    env->GetJavaVM(&s_java_vm);
    s_plugin_instance = env->NewGlobalRef(plugin);

    auto plugin_class = env->GetObjectClass(plugin);
    if (!plugin_class)
        return;

    s_bind_webcontent_service_method = env->GetMethodID(plugin_class, "bindWebContentServiceFromNative", "(I)V");
    if (!s_bind_webcontent_service_method) {
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
    }
    env->DeleteLocalRef(plugin_class);
}

static ErrorOr<void> bind_webcontent_service_java(int ipc_socket)
{
    if (!s_java_vm || !s_plugin_instance || !s_bind_webcontent_service_method)
        return Error::from_string_literal("Android plugin instance not registered for WebContent binding");

    JNIEnv* env = nullptr;
    bool did_attach = false;
    auto get_env_result = s_java_vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (get_env_result == JNI_EDETACHED) {
        if (s_java_vm->AttachCurrentThread(&env, nullptr) != JNI_OK)
            return Error::from_string_literal("Failed to attach current thread to JVM");
        did_attach = true;
    } else if (get_env_result != JNI_OK || !env) {
        return Error::from_string_literal("Failed to acquire JNI environment");
    }

    env->CallVoidMethod(s_plugin_instance, s_bind_webcontent_service_method, ipc_socket);
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        if (did_attach)
            s_java_vm->DetachCurrentThread();
        return Error::from_string_literal("bindWebContentServiceFromNative threw a Java exception");
    }

    if (did_attach)
        s_java_vm->DetachCurrentThread();

    return {};
}
#else
#define LADYBIRD_LOGI(...)
#define LADYBIRD_LOGE(...)
#endif

std::mutex g_web_views_mutex;
int g_next_view_id = 1;
int g_active_view_id = -1;

AskUserForDownloadPathCallback g_ask_user_for_download_path_callback = nullptr;
DisplayDownloadConfirmationDialogCallback g_display_download_confirmation_dialog_callback = nullptr;
DisplayErrorDialogCallback g_display_error_dialog_callback = nullptr;

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
#elif defined(__ANDROID__)
    std::vector<u8> m_pixel_buffer;
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
    bool m_client_ready = false;
    std::chrono::steady_clock::time_point m_last_initialize_attempt {};

    std::mutex m_mutex;

    void configure_client_process()
    {
        auto theme_path = LexicalPath::join(WebView::s_ladybird_resource_root, "themes"sv, "Default.ini"sv);
        auto maybe_theme = Gfx::load_system_theme(theme_path.string());
        if (maybe_theme.is_error())
        {
            auto error = maybe_theme.release_error();
            LADYBIRD_LOGE("Failed to load theme from %s (code=%d)", theme_path.string().characters(), error.code());
            fprintf(stderr, "[Ladybird] Failed to load theme from %s (code=%d)\n", theme_path.string().characters(), error.code());
        }
        else
        {
            client().async_update_system_theme(m_client_state.page_index, maybe_theme.release_value());
        }

        client().async_set_viewport(m_client_state.page_index, viewport_size(), m_zoom);
        client().async_set_window_size(m_client_state.page_index, viewport_size());

        Web::DevicePixelRect screen_rect{0, 0, 1920, 1080};
        client().async_update_screen_rects(m_client_state.page_index, {{screen_rect}}, 0);
    }

#if defined(__ANDROID__)
    ErrorOr<NonnullRefPtr<WebView::WebContentClient>> bind_web_content_client()
    {
        int socket_fds[2] {};
        TRY(Core::System::socketpair(AF_LOCAL, SOCK_STREAM, 0, socket_fds));

        int ui_fd = socket_fds[0];
        int wc_fd = socket_fds[1];

        auto bind_result = bind_webcontent_service_java(wc_fd);
        if (bind_result.is_error()) {
            MUST(Core::System::close(ui_fd));
            MUST(Core::System::close(wc_fd));
            return bind_result.release_error();
        }

        auto socket = TRY(Core::LocalSocket::adopt_fd(ui_fd));
        TRY(socket->set_blocking(true));

        return TRY(try_make_ref_counted<WebView::WebContentClient>(make<IPC::Transport>(move(socket)), *this));
    }
#endif

    virtual void initialize_client(CreateNewClient create_new_client = CreateNewClient::Yes) override
    {
        m_last_initialize_attempt = std::chrono::steady_clock::now();

#if defined(__ANDROID__)
        (void)create_new_client;
        m_client_state = {};

        auto new_client = bind_web_content_client();
        if (new_client.is_error()) {
            m_client_ready = false;
            LADYBIRD_LOGE("initialize_client failed to bind WebContent service: %s", new_client.error().string_literal());
            return;
        }

        m_client_state.client = new_client.release_value();
        m_client_state.client_handle = MUST(Web::Crypto::generate_random_uuid());
        client().async_set_window_handle(0, m_client_state.client_handle);
#else
        ViewImplementation::initialize_client(create_new_client);
        if (!m_client_state.client) {
            m_client_ready = false;
            LADYBIRD_LOGE("initialize_client failed to create WebContent client");
            return;
        }
#endif

        m_client_ready = true;

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
                auto bitmap = m_client_state.front_bitmap.bitmap;
                if (bitmap)
                {
                    std::lock_guard<std::mutex> lock(m_mutex);
                    bool size_changed = (bitmap->width() != m_width || bitmap->height() != m_height);
                    m_width = bitmap->width();
                    m_height = bitmap->height();

#if defined(__ANDROID__)
                    auto pixel_count = static_cast<size_t>(m_width) * static_cast<size_t>(m_height) * 4;
                    m_pixel_buffer.resize(pixel_count);
                    memcpy(m_pixel_buffer.data(), bitmap->scanline_u8(0), pixel_count);
#else
                    // Linux implementation uses Gfx::Bitmap directly from m_client_state.
                    m_bitmap = bitmap;
#endif

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

    void retry_initialize_if_needed()
    {
#if defined(__ANDROID__)
        if (m_client_ready)
            return;

        auto now = std::chrono::steady_clock::now();
        if (m_last_initialize_attempt.time_since_epoch().count() != 0) {
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - m_last_initialize_attempt);
            if (elapsed.count() < 1000)
                return;
        }

        initialize_client();
#endif
    }

    void resize(int width, int height)
    {
        if (!m_client_ready)
            return;
        auto size = Web::DevicePixelSize{width, height};
        client().async_set_viewport(m_client_state.page_index, size, m_zoom);
        client().async_set_window_size(m_client_state.page_index, size);
    }

    void update_zoom_scale()
    {
        if (!m_client_ready)
            return;
        auto size = Web::DevicePixelSize{m_width, m_height};
        client().async_set_viewport(m_client_state.page_index, size, m_zoom);
    }

    void dispatch_mouse_event(Web::MouseEvent::Type type, int x, int y, int button, int buttons, int modifiers, int wheel_delta_x, int wheel_delta_y)
    {
        if (!m_client_ready)
            return;
        Web::DevicePixelPoint position = {x, y};
        Web::DevicePixelPoint screen_position = {x, y};
        enqueue_input_event(Web::MouseEvent{type, position, screen_position, static_cast<Web::UIEvents::MouseButton>(button), static_cast<Web::UIEvents::MouseButton>(buttons), static_cast<Web::UIEvents::KeyModifier>(modifiers), wheel_delta_x, wheel_delta_y, nullptr});
    }

    void dispatch_key_event(Web::KeyEvent::Type type, int keycode, int modifiers, uint32_t code_point, bool repeat)
    {
        if (!m_client_ready)
            return;
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
    FlutterApplication(Optional<ByteString> ladybird_binary_path = {}) : WebView::Application(std::move(ladybird_binary_path)) {}

    virtual ~FlutterApplication() override = default;

    virtual void create_platform_arguments(Core::ArgsParser &) override {}
    virtual void create_platform_options(WebView::BrowserOptions &, WebView::RequestServerOptions &, WebView::WebContentOptions &) override {}

    virtual bool should_capture_web_content_output() const override { return true; }

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
    virtual Optional<ByteString> ask_user_for_download_path(StringView suggestion) const override
    {
        if (g_ask_user_for_download_path_callback)
        {
            auto suggestion_string = suggestion.to_byte_string();
            char *result = g_ask_user_for_download_path_callback(suggestion_string.characters());
            if (result)
            {
                ByteString path(result);
                free(result);
                return path;
            }
        }
        return {};
    }
    virtual void display_download_confirmation_dialog(StringView path, LexicalPath const &lexical_path) const override
    {
        if (g_display_download_confirmation_dialog_callback)
        {
            auto path_string = path.to_byte_string();
            g_display_download_confirmation_dialog_callback(path_string.characters(), lexical_path.string().characters());
        }
    }
    virtual void display_error_dialog(StringView message) const override
    {
        if (g_display_error_dialog_callback)
        {
            auto message_string = message.to_byte_string();
            g_display_error_dialog_callback(message_string.characters());
        }
    }

    virtual Utf16String clipboard_text() const override { return WebView::Application::clipboard_text(); }
    virtual Vector<Web::Clipboard::SystemClipboardRepresentation> clipboard_entries() const override { return WebView::Application::clipboard_entries(); }
    virtual void insert_clipboard_entry(Web::Clipboard::SystemClipboardRepresentation entry) override
    {
        WebView::Application::insert_clipboard_entry(std::move(entry));
    }
};

static AK::OwnPtr<FlutterApplication> s_app;
static AK::OwnPtr<WebView::BrowserProcess> s_browser_process;
static bool s_ladybird_initialized = false;

static void configure_android_user_dirs()
{
#if defined(__ANDROID__)
    // /proc/self/cmdline contains the process/package name (NUL-terminated).
    FILE* cmdline = fopen("/proc/self/cmdline", "rb");
    if (!cmdline)
        return;

    char package_name[256] = { 0 };
    size_t read = fread(package_name, 1, sizeof(package_name) - 1, cmdline);
    fclose(cmdline);
    if (read == 0 || package_name[0] == '\0')
        return;

    std::string home_dir = std::string("/data/user/0/") + package_name;
    std::string base_dir = home_dir + "/files/ladybird";
    std::string config_dir = base_dir + "/config";
    std::string data_dir = base_dir + "/userdata";
    auto ensure_dir = [](std::string const& path)
    {
        if (mkdir(path.c_str(), 0755) != 0 && errno != EEXIST)
            LADYBIRD_LOGE("Failed to create dir %s: errno=%d", path.c_str(), errno);
    };
    ensure_dir(base_dir);
    ensure_dir(config_dir);
    ensure_dir(data_dir);

    setenv("HOME", home_dir.c_str(), 1);
    setenv("XDG_CONFIG_HOME", config_dir.c_str(), 1);
    setenv("XDG_DATA_HOME", data_dir.c_str(), 1);
    LADYBIRD_LOGI("Configured XDG dirs under %s", base_dir.c_str());
#endif
}

void init_ladybird()
{
    if (s_ladybird_initialized)
        return;

    LADYBIRD_LOGI("init_ladybird() begin");

    configure_android_user_dirs();

    AK::set_rich_debug_enabled(true);

    Optional<ByteString> lib_path;

#if defined(__ANDROID__)
    // Android has a different runtime layout than desktop targets.
    // Avoid deriving lib/resource paths from current_executable_path here.
#elif defined(__APPLE__)
    // Do nothing on macos, it should default properly
#else
    auto current_executable_path = Core::System::current_executable_path();
    if (!current_executable_path.is_error())
    {
        auto path = current_executable_path.value();
        auto app_dir = LexicalPath::dirname(path);
        lib_path = LexicalPath::join(app_dir, "lib"sv).string();

        // Use share/Lagom in the bundle as resource root
        auto resource_root = LexicalPath::join(app_dir, "share"sv, "Lagom"sv).string();
        WebView::s_ladybird_resource_root = resource_root;
        Core::ResourceImplementation::install(make<Core::ResourceImplementationFile>(MUST(String::from_byte_string(resource_root))));
    }
    else
    {
        fprintf(stderr, "[Ladybird] Failed to get executable path: %d\n", current_executable_path.error().code());
    }
#endif

    static char const *argv[] = {"Ladybird", nullptr};

    // TODO: I don't really know what this means?
    static AK::StringView string_views[] = {AK::StringView("Ladybird", 8)};
    Main::Arguments arguments = {1, (char **)argv, {string_views, 1}};

    auto app = FlutterApplication::create(arguments, lib_path);
    if (app.is_error())
    {
        auto error = app.release_error();
        std::println("Failed to construct Ladybird Engine Application");
        fprintf(stderr, "[Ladybird] FlutterApplication::create failed: %s (code=%d)\n", error.string_literal(), error.code());
        LADYBIRD_LOGE("FlutterApplication::create failed: %s (code=%d)", error.string_literal(), error.code());
        return;
    }
    s_app = app.release_value();

    s_browser_process = make<WebView::BrowserProcess>();
    s_ladybird_initialized = true;
    LADYBIRD_LOGI("init_ladybird() app=%p browser=%p", s_app.ptr(), s_browser_process.ptr());

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
                fprintf(stderr, "[Ladybird] BrowserProcess requested ExitProcess during init\n");
                LADYBIRD_LOGI("BrowserProcess requested ExitProcess during init");
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

    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    for (auto& [_, view] : g_web_views)
        view->retry_initialize_if_needed();
}

int create_web_view()
{
    if (!s_ladybird_initialized)
        init_ladybird();

    if (!s_ladybird_initialized || !s_app)
    {
        std::println("Ladybird engine is not initialized; refusing to create web view");
        fprintf(stderr, "[Ladybird] init failed: initialized=%d app=%p browser=%p\n", s_ladybird_initialized ? 1 : 0, s_app.ptr(), s_browser_process.ptr());
        LADYBIRD_LOGE("create_web_view denied: initialized=%d app=%p browser=%p", s_ladybird_initialized ? 1 : 0, s_app.ptr(), s_browser_process.ptr());
        return -1;
    }

    LADYBIRD_LOGI("create_web_view proceeding: app=%p browser=%p", s_app.ptr(), s_browser_process.ptr());

    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    int id = g_next_view_id++;
    auto view = FlutterViewImpl::create(id).release_value();
    view->initialize_client();
    g_web_views[id] = std::move(view);

    if (g_active_view_id == -1)
    {
        g_active_view_id = id;
    }
    std::printf("returning with id = %d", id);
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
    {
        std::printf("could not find webview\n");
        return nullptr;
    }

    std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
#ifdef __APPLE__
    if (!it->second->m_pixel_buffer)
        return nullptr;

    CVPixelBufferRetain(it->second->m_pixel_buffer);
    return it->second->m_pixel_buffer;
#elif defined(__ANDROID__)
    if (it->second->m_pixel_buffer.empty())
        return nullptr;
    return it->second->m_pixel_buffer.data();
#else

    if (!it->second->m_bitmap)
    {
        std::printf("could not find m_bitmap\n");
        return nullptr;
    }

    // Return pointer to the raw pixel data
    // Assuming ARGB format which Flutter expects
    // We return the raw data pointer from Gfx::Bitmap
    return const_cast<u8 *>(it->second->m_bitmap->scanline_u8(0));
#endif
}

int get_pixel_buffer_size(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it == g_web_views.end())
        return 0;

    std::lock_guard<std::mutex> view_lock(it->second->m_mutex);
#if defined(__ANDROID__)
    return static_cast<int>(it->second->m_pixel_buffer.size());
#else
    auto width = it->second->m_width;
    auto height = it->second->m_height;
    if (width <= 0 || height <= 0)
        return 0;
    return width * height * 4;
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
        if (!it->second->m_client_ready)
            return;
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
#elif defined(__ANDROID__)
    return it->second->m_width;
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
#elif defined(__ANDROID__)
    return it->second->m_height;
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
        if (!it->second->m_client_ready)
            return;
        it->second->reload();
    }
}

void go_back(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        if (!it->second->m_client_ready)
            return;
        it->second->traverse_the_history_by_delta(-1);
    }
}

void go_forward(int view_id)
{
    std::lock_guard<std::mutex> lock(g_web_views_mutex);
    auto it = g_web_views.find(view_id);
    if (it != g_web_views.end())
    {
        if (!it->second->m_client_ready)
            return;
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

void set_ask_user_for_download_path_callback(AskUserForDownloadPathCallback callback)
{
    g_ask_user_for_download_path_callback = callback;
}

void set_display_download_confirmation_dialog_callback(DisplayDownloadConfirmationDialogCallback callback)
{
    g_display_download_confirmation_dialog_callback = callback;
}

void set_display_error_dialog_callback(DisplayErrorDialogCallback callback)
{
    g_display_error_dialog_callback = callback;
}

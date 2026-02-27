#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <thread>
#include <mutex>

#include <LibCore/EventLoop.h>
#include <LibGfx/Bitmap.h>
#include <WebView/ViewImplementation.h>
#include <AK/URL.h>

// raaa

std::mutex g_frame_mutex;
uint8_t* g_latest_frame = nullptr;
int g_width = 800;
int g_height = 600;

class FlutterViewImpl final : public WebView::ViewImplementation {
public:
    static AK::ErrorOr<AK::NonnullOwnPtr<FlutterViewImpl>> create() {
        return AK::adopt_nonnull_own_or_enomem(new (std::nothrow) FlutterViewImpl());
    }

    virtual void initialize_client(WebView::UseLagomNetworking use_networking) override {
        ViewImplementation::initialize_client(use_networking);
    }

    virtual void notify_server_did_paint(AK::Badge<WebView::WebContentClient>, i32 bitmap_id, Gfx::IntSize size) override {
        if (auto* bitmap = front_bitmap()) {
            std::lock_guard<std::mutex> lock(g_frame_mutex);
            
            if (size.width() != g_width || size.height() != g_height || !g_latest_frame) {
                g_width = size.width();
                g_height = size.height();
                delete[] g_latest_frame;
                g_latest_frame = new uint8_t[g_width * g_height * 4];
            }

            memcpy(g_latest_frame, bitmap->scanline(0), g_width * g_height * 4);
        }
    }

    virtual void update_zoom() override {}
    virtual void set_viewport_rect(Gfx::IntRect const&) override {}
    virtual Gfx::IntRect viewport_rect() const override { return { 0, 0, g_width, g_height }; }
    virtual Gfx::IntPoint to_content_position(Gfx::IntPoint widget_position) const override { return widget_position; }
    virtual Gfx::IntPoint to_widget_position(Gfx::IntPoint content_position) const override { return content_position; }
};

AK::OwnPtr<FlutterViewImpl> g_web_view;

extern "C" {
    __attribute__((visibility("default"))) __attribute__((used))
    void init_ladybird() {
        static std::thread ladybird_thread([]() {
            Core::EventLoop loop;
            
            g_web_view = FlutterViewImpl::create().release_value_but_fixme_should_propagate_errors();
            g_web_view->initialize_client(WebView::UseLagomNetworking::Yes);
            
            g_web_view->load(AK::URL::create_with_url_or_path("https://ladybird.dev"));
            
            loop.exec();
        });
        ladybird_thread.detach();
    }

    __attribute__((visibility("default"))) __attribute__((used))
    uint8_t* get_latest_frame(int* out_width, int* out_height) {
        std::lock_guard<std::mutex> lock(g_frame_mutex);
        if (!g_latest_frame) return nullptr;

        *out_width = g_width;
        *out_height = g_height;
        
        int size = g_width * g_height * 4;
        uint8_t* buffer_copy = (uint8_t*)malloc(size);
        memcpy(buffer_copy, g_latest_frame, size);
        
        return buffer_copy;
    }

    __attribute__((visibility("default"))) __attribute__((used))
    void free_frame(uint8_t* buffer) {
        free(buffer);
    }
}
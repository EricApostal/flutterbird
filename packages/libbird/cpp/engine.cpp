#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <thread>
#include <mutex>

#include <LibCore/EventLoop.h>
#include <LibGfx/Bitmap.h>
#include <LibWebView/ViewImplementation.h>
#include <LibURL/URL.h>

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
    }

private:
    FlutterViewImpl() {}

    virtual void update_zoom() override {}
    virtual Web::DevicePixelSize viewport_size() const override { return { g_width, g_height }; }
    virtual Gfx::IntPoint to_content_position(Gfx::IntPoint widget_position) const override { return widget_position; }
    virtual Gfx::IntPoint to_widget_position(Gfx::IntPoint content_position) const override { return content_position; }
};

AK::OwnPtr<FlutterViewImpl> g_web_view;

#include "engine.h"

void init_ladybird() {
    static std::thread ladybird_thread([]() {
        Core::EventLoop loop;
        
        g_web_view = FlutterViewImpl::create().release_value_but_fixme_should_propagate_errors();
        g_web_view->initialize_client();
        
        g_web_view->load(URL::create_with_url_or_path("https://ladybird.dev").value());
        
        loop.exec();
    });
    ladybird_thread.detach();
}

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

void free_frame(uint8_t* buffer) {
    free(buffer);
}
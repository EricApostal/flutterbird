#include "../../../../third_party/ladybird/UI/Android/src/main/cpp/LadybirdServiceBase.h"

#include <AK/ErrorOr.h>
#include <AK/OwnPtr.h>
#include <AK/StdLibExtras.h>
#include <AK/Try.h>
#include <Compositor/ConnectionFromClient.h>
#include <LibCore/EventLoop.h>
#include <LibCore/LocalSocket.h>
#include <LibGfx/SkiaBackendContext.h>
#include <LibIPC/Transport.h>
#include <LibWebView/Utilities.h>

ErrorOr<int> service_main(int ipc_socket)
{
    Core::EventLoop event_loop;

    WebView::platform_init();
    Gfx::SkiaBackendContext::initialize_gpu_backend();
    auto skia_backend_context = Gfx::SkiaBackendContext::the_main_thread_context();

    auto socket = TRY(Core::LocalSocket::adopt_fd(ipc_socket));
    [[maybe_unused]] auto compositor = TRY(Compositor::ConnectionFromClient::try_create(
        make<IPC::Transport>(move(socket)), move(skia_backend_context), true));

    return event_loop.exec();
}

#include "view_backend.h"

void ViewBackend::fire_frame_ready(bool size_changed) {
  // Snapshot the callbacks under the lock so we never hold it while
  // invoking user code (avoids potential re-entrance deadlocks).
  FrameCallback cb = nullptr;
  void *ctx = nullptr;
  ResizeCallback resize = nullptr;

  {
    std::lock_guard lock(callback_mutex);
    cb = frame_callback;
    ctx = frame_callback_context;
    resize = resize_callback;
  }

  if (size_changed && resize)
    resize();

  if (cb)
    cb(ctx);
}

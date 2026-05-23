/*
 * Abstract ViewBackend — one concrete subclass per host platform.
 *
 * Responsibilities:
 *  - Ingest rendered frames from the WebContent process in a
 *    platform-appropriate form (Gfx::Bitmap on Linux, IOSurface/
 *    CVPixelBuffer on macOS).
 *  - Expose the raw pixel data pointer and frame dimensions that the
 *    Flutter engine plugin needs.
 *  - Manage the FrameCallback / ResizeCallback lifetime safely across
 *    the threads that may trigger them.
 *
 * Frame-ingestion contract
 * ────────────────────────
 * FlutterViewImpl::initialize_client() sets the ViewImplementation
 * on_ready_to_paint callback.  That lambda extracts the bitmap /
 * IOSurface from m_client_state and calls the appropriate method on
 * the backend:
 *
 *   Linux / fallback:  on_bitmap_ready(Gfx::Bitmap const)
 *   macOS (future):    MacOSViewBackend::on_iosurface_ready(…)
 *
 * All #ifdef __APPLE__ guards are confined to that lambda and to the
 * factory that creates the concrete backend — nowhere else.
 */

#pragma once

#include "../engine.h"

#include <AK/RefPtr.h>
#include <LibGfx/Bitmap.h>

#include <mutex>

class ViewBackend {
public:
  virtual ~ViewBackend() = default;

  // ── Frame ingestion ──────────────────────────────────────────────────
  //
  // Called from the on_ready_to_paint lambda in FlutterViewImpl.
  // The default implementation is a no-op so that platforms that use
  // a different ingestion path (e.g. macOS IOSurface) only need to
  // override the method that is relevant to them.
  virtual void on_bitmap_ready(AK::RefPtr<Gfx::Bitmap const> bitmap) {
    (void)bitmap;
  }

  // ── Output ───────────────────────────────────────────────────────────
  //
  // Returns a pointer to the current frame's pixel data, or nullptr
  // if no frame has been received yet.
  //
  //   Linux:  u8* into the Gfx::Bitmap scanline buffer.
  //           Valid until the next on_bitmap_ready() call.
  //   macOS:  CVPixelBufferRef (retained — caller must CFRelease).
  virtual void *pixel_data() = 0;

  // Dimensions of the most recently ingested frame.
  virtual int width() const = 0;
  virtual int height() const = 0;

  // ── Callback management ──────────────────────────────────────────────
  //
  // Set by engine.cpp glue functions; read inside fire_frame_ready().
  // All access is serialised by callback_mutex.
  std::mutex callback_mutex;
  FrameCallback frame_callback{nullptr};
  void *frame_callback_context{nullptr};
  ResizeCallback resize_callback{nullptr};

protected:
  ViewBackend() = default;

  // Fires resize_callback (when size_changed is true) then
  // frame_callback, without holding any internal bitmap lock.
  void fire_frame_ready(bool size_changed);
};

/*
 * macOS ViewBackend — placeholder for the IOSurface / CVPixelBuffer path.
 *
 * On macOS, the WebContent process renders into an IOSurface.  The ideal
 * Flutter integration wraps that IOSurface in a CVPixelBuffer and uploads
 * it as an external GPU texture, avoiding any CPU-side pixel copy.
 *
 * This class is intentionally left unimplemented.
 * When adding proper macOS support:
 *
 *  1. Add on_iosurface_ready() that calls CVPixelBufferCreateWithIOSurface
 *     and stores the resulting CVPixelBufferRef in m_pixel_buffer.
 *  2. pixel_data() should return a retained CVPixelBufferRef; the Flutter
 *     plugin releases it after uploading the GPU texture each frame.
 *  3. Update FlutterViewImpl::initialize_client's on_ready_to_paint lambda
 *     to extract the IOSurface and call on_iosurface_ready() instead of
 *     on_bitmap_ready().
 *
 * Until then, on_bitmap_ready() provides a CPU fallback (useful for
 * testing on macOS before the GPU path is ready).
 */

#pragma once

#ifdef __APPLE__

#include "view_backend.h"

#include <CoreVideo/CoreVideo.h>
#include <IOSurface/IOSurface.h>

class MacOSViewBackend final : public ViewBackend {
public:
  MacOSViewBackend() = default;
  ~MacOSViewBackend() override;

  // Primary macOS path: wrap Ladybird's IOSurface into CVPixelBuffer.
  bool on_iosurface_ready(IOSurfaceRef surface, int width, int height);

  // CPU fallback: store bitmap and materialize CVPixelBuffer when surface is
  // not available.
  void on_bitmap_ready(AK::RefPtr<Gfx::Bitmap const> bitmap) override;

  // Future GPU path: CVPixelBufferRef wrapping the rendered IOSurface.
  // void on_iosurface_ready(IOSurfaceRef surface, int width, int height);

  // Returns a retained CVPixelBufferRef (caller releases).
  // Never returns raw bitmap bytes on macOS.
  void *pixel_data() override;
  uint64_t frame_generation() const override;
  int width() const override;
  int height() const override;

private:
  mutable std::mutex m_mutex;
  // CPU fallback bitmap (used until the IOSurface path is ready):
  AK::RefPtr<Gfx::Bitmap const> m_bitmap;
  // GPU texture path (TODO):
  CVPixelBufferRef m_pixel_buffer{nullptr};
  uint64_t m_generation{0};
  int m_width{800};
  int m_height{600};
};

#endif // __APPLE__

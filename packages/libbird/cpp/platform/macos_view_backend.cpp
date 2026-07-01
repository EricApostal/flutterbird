#include "macos_view_backend.h"

#ifdef __APPLE__

#include <algorithm>
#include <cstring>

// CVPixelBufferCreateWithIOSurface() otherwise reports the IOSurface's literal
// backing dimensions (which can be padded/aligned larger than what was actually
// requested/painted) via CVPixelBufferGetWidth/Height -- and that's what Flutter's
// external texture path reads to size what it renders, regardless of any size
// bookkeeping done elsewhere. Passing kCVPixelBufferWidthKey/HeightKey explicitly
// makes Core Video report (and crop to) the size Ladybird was actually asked to
// paint at, instead of the surface's true/padded allocation size.
static CVPixelBufferRef create_pixel_buffer_from_iosurface(IOSurfaceRef surface,
                                                           int width,
                                                           int height) {
  if (!surface)
    return nullptr;

  auto surface_width = static_cast<int>(IOSurfaceGetWidth(surface));
  auto surface_height = static_cast<int>(IOSurfaceGetHeight(surface));
  bool use_explicit_size = width > 0 && height > 0 && width <= surface_width &&
                           height <= surface_height;

  CFMutableDictionaryRef attributes = CFDictionaryCreateMutable(
      kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  if (!attributes)
    return nullptr;

  CFDictionarySetValue(attributes, kCVPixelBufferMetalCompatibilityKey,
                       kCFBooleanTrue);

  if (use_explicit_size) {
    auto *width_number =
        CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &width);
    auto *height_number =
        CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &height);
    if (width_number)
      CFDictionarySetValue(attributes, kCVPixelBufferWidthKey, width_number);
    if (height_number)
      CFDictionarySetValue(attributes, kCVPixelBufferHeightKey, height_number);
    if (width_number)
      CFRelease(width_number);
    if (height_number)
      CFRelease(height_number);
  }

  CVPixelBufferRef pixel_buffer = nullptr;
  auto cv_result = CVPixelBufferCreateWithIOSurface(
      kCFAllocatorDefault, surface, attributes, &pixel_buffer);
  CFRelease(attributes);
  if (cv_result != kCVReturnSuccess || !pixel_buffer)
    return nullptr;
  return pixel_buffer;
}

static CVPixelBufferRef create_pixel_buffer_from_bitmap(Gfx::Bitmap const &bitmap) {
  if (bitmap.width() <= 0 || bitmap.height() <= 0)
    return nullptr;

  // Request an IOSurface-backed, Metal-compatible pixel buffer so Flutter's
  // external texture path can import it reliably.
  auto *empty_surface_properties = CFDictionaryCreate(
      kCFAllocatorDefault, nullptr, nullptr, 0,
      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  if (!empty_surface_properties)
    return nullptr;

  const void *keys[] = {kCVPixelBufferIOSurfacePropertiesKey,
                        kCVPixelBufferMetalCompatibilityKey};
  const void *values[] = {empty_surface_properties, kCFBooleanTrue};
  auto *attributes = CFDictionaryCreate(
      kCFAllocatorDefault, keys, values, 2, &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  CFRelease(empty_surface_properties);
  if (!attributes)
    return nullptr;

  CVPixelBufferRef pixel_buffer = nullptr;
  auto cv_result = CVPixelBufferCreate(
      kCFAllocatorDefault, bitmap.width(), bitmap.height(),
      kCVPixelFormatType_32BGRA, attributes, &pixel_buffer);
  CFRelease(attributes);
  if (cv_result != kCVReturnSuccess || !pixel_buffer)
    return nullptr;

  auto lock_result = CVPixelBufferLockBaseAddress(pixel_buffer, 0);
  if (lock_result != kCVReturnSuccess) {
    CVPixelBufferRelease(pixel_buffer);
    return nullptr;
  }

  auto *dst = static_cast<uint8_t *>(CVPixelBufferGetBaseAddress(pixel_buffer));
  auto dst_stride = CVPixelBufferGetBytesPerRow(pixel_buffer);
  auto const src_stride = static_cast<size_t>(bitmap.pitch());
  auto const row_bytes = std::min(dst_stride, src_stride);

  if (!dst || row_bytes == 0) {
    CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
    CVPixelBufferRelease(pixel_buffer);
    return nullptr;
  }

  for (int y = 0; y < bitmap.height(); ++y)
    std::memcpy(dst + (static_cast<size_t>(y) * dst_stride), bitmap.scanline_u8(y),
                row_bytes);

  CVPixelBufferUnlockBaseAddress(pixel_buffer, 0);
  return pixel_buffer;
}

bool MacOSViewBackend::on_iosurface_ready(IOSurfaceRef surface, int width,
                                          int height) {
  if (!surface || width <= 0 || height <= 0)
    return false;

  auto surface_width = static_cast<int>(IOSurfaceGetWidth(surface));
  auto surface_height = static_cast<int>(IOSurfaceGetHeight(surface));

  bool size_changed = false;
  bool has_pixel_buffer = false;
  bool should_publish = false;
  {
    std::lock_guard lock(m_mutex);

    // The surface hasn't grown to fit the requested (broadcast) size yet --
    // e.g. mid-resize, before Ladybird's compositor has reallocated its
    // backing store to match. Don't publish a frame cropped/reported at some
    // smaller, stale size (that reads as the viewport having shrunk, even
    // though it never actually did). Keep showing whatever frame we already
    // have -- Flutter will just stretch that to fill the box, which is
    // already sized correctly since it comes from the broadcast value
    // directly, not from this backend -- until a surface big enough to
    // satisfy the request arrives.
    if (width > surface_width || height > surface_height) {
      has_pixel_buffer = (m_pixel_buffer != nullptr);
    } else {
      size_changed = (width != m_width || height != m_height);
      m_width = width;
      m_height = height;

      if (surface != m_surface || !m_pixel_buffer || size_changed) {
        auto *new_pixel_buffer =
            create_pixel_buffer_from_iosurface(surface, width, height);
        if (!new_pixel_buffer)
          return false;

        if (m_pixel_buffer) {
          CVPixelBufferRelease(m_pixel_buffer);
          m_pixel_buffer = nullptr;
        }
        if (m_surface) {
          CFRelease(m_surface);
          m_surface = nullptr;
        }

        m_pixel_buffer = new_pixel_buffer;
        m_surface = surface;
        CFRetain(m_surface);
      }

      has_pixel_buffer = (m_pixel_buffer != nullptr);
      if (has_pixel_buffer) {
        ++m_generation;
        should_publish = true;
      }
    }
  }

  if (should_publish)
    fire_frame_ready(size_changed);

  return has_pixel_buffer;
}

MacOSViewBackend::~MacOSViewBackend() {
  std::lock_guard lock(m_mutex);
  if (m_pixel_buffer) {
    CVPixelBufferRelease(m_pixel_buffer);
    m_pixel_buffer = nullptr;
  }
  if (m_surface) {
    CFRelease(m_surface);
    m_surface = nullptr;
  }
}

void MacOSViewBackend::on_bitmap_ready(AK::RefPtr<Gfx::Bitmap const> bitmap) {
  if (!bitmap)
    return;

  bool size_changed = false;
  {
    std::lock_guard lock(m_mutex);
    size_changed = (bitmap->width() != m_width || bitmap->height() != m_height);
    m_bitmap = std::move(bitmap);
    m_width = m_bitmap->width();
    m_height = m_bitmap->height();

    if (m_surface) {
      CFRelease(m_surface);
      m_surface = nullptr;
    }

    auto *new_pixel_buffer = create_pixel_buffer_from_bitmap(*m_bitmap);
    if (m_pixel_buffer) {
      CVPixelBufferRelease(m_pixel_buffer);
      m_pixel_buffer = nullptr;
    }
    m_pixel_buffer = new_pixel_buffer;
    if (m_pixel_buffer)
      ++m_generation;
  }

  fire_frame_ready(size_changed);
}

void *MacOSViewBackend::pixel_data() {
  std::lock_guard lock(m_mutex);

  if (m_pixel_buffer) {
    CVPixelBufferRetain(m_pixel_buffer);
    return m_pixel_buffer;
  }

  return nullptr;
}

uint64_t MacOSViewBackend::frame_generation() const {
  std::lock_guard lock(m_mutex);
  return m_generation;
}

int MacOSViewBackend::width() const {
  std::lock_guard lock(m_mutex);
  return m_width;
}

int MacOSViewBackend::height() const {
  std::lock_guard lock(m_mutex);
  return m_height;
}

IOSurfaceRef MacOSViewBackend::latest_surface() const {
  std::lock_guard lock(m_mutex);
  if (!m_surface)
    return nullptr;
  CFRetain(m_surface);
  return m_surface;
}

#endif // __APPLE__

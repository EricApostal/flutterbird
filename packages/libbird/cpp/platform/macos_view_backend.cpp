#include "macos_view_backend.h"

#ifdef __APPLE__

MacOSViewBackend::~MacOSViewBackend() {
  std::lock_guard lock(m_mutex);
  if (m_pixel_buffer) {
    CVPixelBufferRelease(m_pixel_buffer);
    m_pixel_buffer = nullptr;
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
  }

  fire_frame_ready(size_changed);
}

void *MacOSViewBackend::pixel_data() {
  std::lock_guard lock(m_mutex);

  if (m_pixel_buffer) {
    CVPixelBufferRetain(m_pixel_buffer);
    return m_pixel_buffer;
  }

  if (!m_bitmap)
    return nullptr;

  return const_cast<uint8_t *>(m_bitmap->scanline_u8(0));
}

int MacOSViewBackend::width() const {
  std::lock_guard lock(m_mutex);
  return m_width;
}

int MacOSViewBackend::height() const {
  std::lock_guard lock(m_mutex);
  return m_height;
}

#endif // __APPLE__

#include "linux_view_backend.h"

void LinuxViewBackend::on_bitmap_ready(AK::RefPtr<Gfx::Bitmap const> bitmap) {
  if (!bitmap)
    return;

  bool size_changed = false;
  {
    std::lock_guard lock(m_bitmap_mutex);
    size_changed = (bitmap->width() != m_width || bitmap->height() != m_height);
    m_bitmap = std::move(bitmap);
    m_width = m_bitmap->width();
    m_height = m_bitmap->height();
  }
  // Fire callbacks outside the bitmap lock to prevent re-entrance
  // deadlocks if a callback tries to call pixel_data().
  fire_frame_ready(size_changed);
}

void *LinuxViewBackend::pixel_data() {
  std::lock_guard lock(m_bitmap_mutex);
  if (!m_bitmap)
    return nullptr;
  // Raw pointer into the Gfx::Bitmap scanline buffer (BGRA layout).
  // Valid until the next on_bitmap_ready() call.
  return const_cast<uint8_t *>(m_bitmap->scanline_u8(0));
}

int LinuxViewBackend::width() const {
  std::lock_guard lock(m_bitmap_mutex);
  return m_width;
}

int LinuxViewBackend::height() const {
  std::lock_guard lock(m_bitmap_mutex);
  return m_height;
}

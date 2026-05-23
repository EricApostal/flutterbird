#include "linux_view_backend.h"

#include <cstring>

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
    ++m_frame_generation;
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

bool LinuxViewBackend::copy_pixels_into(uint8_t *out_buffer,
                                        size_t out_capacity, int &out_width,
                                        int &out_height) const {
  std::lock_guard lock(m_bitmap_mutex);
  if (!m_bitmap || !out_buffer)
    return false;

  auto width = m_bitmap->width();
  auto height = m_bitmap->height();
  if (width <= 0 || height <= 0)
    return false;

  size_t row_bytes = static_cast<size_t>(width) * 4;
  size_t required = row_bytes * static_cast<size_t>(height);
  if (out_capacity < required)
    return false;

  auto src_pitch = static_cast<size_t>(m_bitmap->pitch());
  auto *src = m_bitmap->scanline_u8(0);
  for (int y = 0; y < height; ++y) {
    std::memcpy(out_buffer + (static_cast<size_t>(y) * row_bytes),
                src + (static_cast<size_t>(y) * src_pitch), row_bytes);
  }

  out_width = width;
  out_height = height;
  return true;
}

uint64_t LinuxViewBackend::frame_generation() const {
  std::lock_guard lock(m_bitmap_mutex);
  return m_frame_generation;
}

int LinuxViewBackend::width() const {
  std::lock_guard lock(m_bitmap_mutex);
  return m_width;
}

int LinuxViewBackend::height() const {
  std::lock_guard lock(m_bitmap_mutex);
  return m_height;
}

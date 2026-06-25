#include "linux_view_backend.h"

#include <cstring>
#include <unistd.h>

LinuxViewBackend::~LinuxViewBackend() {
  std::lock_guard lock(m_bitmap_mutex);
  if (m_dmabuf_fd >= 0) {
    ::close(m_dmabuf_fd);
    m_dmabuf_fd = -1;
  }
}

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

void LinuxViewBackend::on_hardware_frame_ready(int width, int height) {
  bool size_changed = false;
  {
    std::lock_guard lock(m_bitmap_mutex);
    size_changed = (width != m_width || height != m_height);
    m_width = width;
    m_height = height;
    ++m_frame_generation;
  }
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

bool LinuxViewBackend::snapshot_frame(FrameSnapshot &out_snapshot) const {
  std::lock_guard lock(m_bitmap_mutex);
  if (!m_bitmap)
    return false;

  out_snapshot.bitmap = m_bitmap;
  out_snapshot.width = m_width;
  out_snapshot.height = m_height;
  out_snapshot.pitch = m_bitmap->pitch();
  out_snapshot.generation = m_frame_generation;
  return true;
}

bool LinuxViewBackend::snapshot_linux_dmabuf_frame(
    LinuxDmaBufFrameSnapshot &out_snapshot) const {
  std::lock_guard lock(m_bitmap_mutex);
  if (m_dmabuf_fd < 0 || m_dmabuf_width <= 0 || m_dmabuf_height <= 0 ||
      m_dmabuf_pitch <= 0)
    return false;

  int cloned_fd = ::dup(m_dmabuf_fd);
  if (cloned_fd < 0)
    return false;

  out_snapshot.fd = cloned_fd;
  out_snapshot.width = m_dmabuf_width;
  out_snapshot.height = m_dmabuf_height;
  out_snapshot.pitch = m_dmabuf_pitch;
  out_snapshot.drm_format = m_dmabuf_drm_format;
  out_snapshot.modifier = m_dmabuf_modifier;
  out_snapshot.premultiplied = m_dmabuf_premultiplied;
  out_snapshot.generation = m_frame_generation;
  return true;
}

void LinuxViewBackend::set_linux_dmabuf_frame(int source_fd, int width,
                                              int height, int pitch,
                                              uint32_t drm_format,
                                              uint64_t modifier,
                                              bool premultiplied) {
  if (source_fd < 0 || width <= 0 || height <= 0 || pitch <= 0) {
    clear_linux_dmabuf_frame();
    return;
  }

  int owned_fd = ::dup(source_fd);
  if (owned_fd < 0)
    return;

  std::lock_guard lock(m_bitmap_mutex);
  if (m_dmabuf_fd >= 0)
    ::close(m_dmabuf_fd);
  m_dmabuf_fd = owned_fd;
  m_dmabuf_width = width;
  m_dmabuf_height = height;
  m_dmabuf_pitch = pitch;
  m_dmabuf_drm_format = drm_format;
  m_dmabuf_modifier = modifier;
  m_dmabuf_premultiplied = premultiplied;
}

void LinuxViewBackend::clear_linux_dmabuf_frame() {
  std::lock_guard lock(m_bitmap_mutex);
  if (m_dmabuf_fd >= 0) {
    ::close(m_dmabuf_fd);
    m_dmabuf_fd = -1;
  }
  m_dmabuf_width = 0;
  m_dmabuf_height = 0;
  m_dmabuf_pitch = 0;
  m_dmabuf_drm_format = 0;
  m_dmabuf_modifier = 0;
  m_dmabuf_premultiplied = true;
}

int LinuxViewBackend::width() const {
  std::lock_guard lock(m_bitmap_mutex);
  return m_width;
}

int LinuxViewBackend::height() const {
  std::lock_guard lock(m_bitmap_mutex);
  return m_height;
}

/*
 * Linux ViewBackend — stores the latest Gfx::Bitmap received from the
 * WebContent process and exposes raw BGRA pixel data to the Flutter plugin.
 *
 * Frame flow (mirrors the Qt WebContentView pattern):
 *   WebContent renders → ViewImplementation::on_ready_to_paint fires →
 *   FlutterViewImpl extracts the Gfx::Bitmap from m_client_state →
 *   LinuxViewBackend::on_bitmap_ready() is called →
 *   Gfx::Bitmap RefPtr stored under m_bitmap_mutex →
 *   fire_frame_ready() invoked without bitmap lock →
 *   Flutter FrameCallback / ResizeCallback notified.
 *
 * Thread safety:
 *   on_bitmap_ready() and pixel_data() may be called from different
 *   threads.  m_bitmap_mutex serialises access to m_bitmap, m_width,
 *   and m_height.  Callbacks are fired outside m_bitmap_mutex.
 */

#pragma once

#include "view_backend.h"

#include <mutex>

class LinuxViewBackend final : public ViewBackend {
public:
  LinuxViewBackend() = default;

  // ViewBackend overrides
  void on_bitmap_ready(AK::RefPtr<Gfx::Bitmap const> bitmap) override;
  void *pixel_data() override;
  int width() const override;
  int height() const override;

private:
  mutable std::mutex m_bitmap_mutex;
  AK::RefPtr<Gfx::Bitmap const> m_bitmap;
  int m_width{800};
  int m_height{600};
};

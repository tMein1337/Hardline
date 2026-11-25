// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef HARDLINE_SCREENCAST_EGL_DMABUF_H_
#define HARDLINE_SCREENCAST_EGL_DMABUF_H_

#include <EGL/egl.h>

#include <cstdint>
#include <vector>

namespace hardline_screencast {

// One plane of a DMA-BUF as PipeWire hands it over.
struct DmaBufPlane {
  int fd;
  uint32_t offset;
  uint32_t stride;
};

// Reads DMA-BUF frames back into memory through the GPU.
//
// Compositors that share their screen through PipeWire may only offer GPU
// buffers (niri does), which the CPU cannot read directly: tiled layouts,
// vendor modifiers, and on NVIDIA no mmap at all. The buffer is imported as an
// EGLImage, drawn into a texture-backed framebuffer and read with
// glReadPixels, the same route Chromium's and OBS's capturers take.
//
// Uses its own headless EGL display (no window, no surface), separate from
// the one Flutter renders with. Create on any thread; all other calls must
// come from the one thread that captures.
class EglDmaBuf {
 public:
  EglDmaBuf();
  ~EglDmaBuf();

  EglDmaBuf(const EglDmaBuf&) = delete;
  EglDmaBuf& operator=(const EglDmaBuf&) = delete;

  // Whether a display that can import DMA-BUFs was found.
  bool ok() const { return ok_; }

  // Modifiers the GPU can import `drm_format` with, for offering to the
  // compositor. Empty when none, or when DMA-BUF import is unavailable.
  std::vector<uint64_t> QueryModifiers(uint32_t drm_format);

  // Imports one frame and reads it into `rgba` as tightly packed R,G,B,A
  // bytes. Returns false when the import fails, which usually means the
  // compositor picked a modifier this GPU cannot read after all.
  bool ReadPixels(uint32_t drm_format, uint64_t modifier, int width,
                  int height, const std::vector<DmaBufPlane>& planes,
                  std::vector<uint8_t>* rgba);

 private:
  bool MakeCurrent();

  bool ok_ = false;
  bool has_modifiers_ = false;
  EGLDisplay display_ = EGL_NO_DISPLAY;
  EGLContext context_ = EGL_NO_CONTEXT;
  bool gl_ready_ = false;
  unsigned int texture_ = 0;
  unsigned int framebuffer_ = 0;
};

}  // namespace hardline_screencast

#endif  // HARDLINE_SCREENCAST_EGL_DMABUF_H_

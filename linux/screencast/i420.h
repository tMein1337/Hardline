// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef HARDLINE_SCREENCAST_I420_H_
#define HARDLINE_SCREENCAST_I420_H_

#include <cstdint>
#include <vector>

namespace hardline_screencast {

// Byte positions of red, green and blue inside one 4-byte pixel.
struct PixelLayout {
  int r;
  int g;
  int b;
};

// One I420 picture in a single buffer: Y, then U, then V, without padding.
struct I420Picture {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> data;

  int stride_y() const { return width; }
  int stride_uv() const { return (width + 1) / 2; }
  uint8_t* y() { return data.data(); }
  uint8_t* u() { return y() + stride_y() * height; }
  uint8_t* v() { return u() + stride_uv() * ((height + 1) / 2); }
};

// Converts packed 32-bit RGB (any byte order, alpha ignored) to I420 with
// BT.601 limited-range coefficients, which is what WebRTC's encoders assume
// for an untagged frame. `dst` is resized to fit.
void ConvertToI420(const uint8_t* src, int src_stride, int width, int height,
                   PixelLayout layout, I420Picture* dst);

}  // namespace hardline_screencast

#endif  // HARDLINE_SCREENCAST_I420_H_

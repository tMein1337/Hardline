// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "i420.h"

namespace hardline_screencast {

namespace {

inline uint8_t LumaOf(int r, int g, int b) {
  return static_cast<uint8_t>(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
}

}  // namespace

void ConvertToI420(const uint8_t* src, int src_stride, int width, int height,
                   PixelLayout layout, I420Picture* dst) {
  const int chroma_width = (width + 1) / 2;
  const int chroma_height = (height + 1) / 2;
  dst->width = width;
  dst->height = height;
  dst->data.resize(static_cast<size_t>(width) * height +
                   2 * static_cast<size_t>(chroma_width) * chroma_height);

  uint8_t* y_plane = dst->y();
  uint8_t* u_plane = dst->u();
  uint8_t* v_plane = dst->v();
  const int ri = layout.r;
  const int gi = layout.g;
  const int bi = layout.b;

  // Two rows at a time: each 2x2 block shares one U and one V sample, taken
  // from the average of its four pixels. An odd last row or column repeats
  // its neighbour.
  for (int row = 0; row < height; row += 2) {
    const uint8_t* line0 = src + static_cast<size_t>(row) * src_stride;
    const uint8_t* line1 =
        row + 1 < height ? line0 + src_stride : line0;
    uint8_t* y0 = y_plane + static_cast<size_t>(row) * width;
    uint8_t* y1 = row + 1 < height ? y0 + width : nullptr;
    uint8_t* u = u_plane + static_cast<size_t>(row / 2) * chroma_width;
    uint8_t* v = v_plane + static_cast<size_t>(row / 2) * chroma_width;

    for (int col = 0; col < width; col += 2) {
      const int next = col + 1 < width ? 4 : 0;
      const uint8_t* p00 = line0 + col * 4;
      const uint8_t* p01 = p00 + next;
      const uint8_t* p10 = line1 + col * 4;
      const uint8_t* p11 = p10 + next;

      y0[col] = LumaOf(p00[ri], p00[gi], p00[bi]);
      if (next) y0[col + 1] = LumaOf(p01[ri], p01[gi], p01[bi]);
      if (y1) {
        y1[col] = LumaOf(p10[ri], p10[gi], p10[bi]);
        if (next) y1[col + 1] = LumaOf(p11[ri], p11[gi], p11[bi]);
      }

      const int r = (p00[ri] + p01[ri] + p10[ri] + p11[ri] + 2) >> 2;
      const int g = (p00[gi] + p01[gi] + p10[gi] + p11[gi] + 2) >> 2;
      const int b = (p00[bi] + p01[bi] + p10[bi] + p11[bi] + 2) >> 2;
      u[col / 2] =
          static_cast<uint8_t>(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128);
      v[col / 2] =
          static_cast<uint8_t>(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128);
    }
  }
}

}  // namespace hardline_screencast

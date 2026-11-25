// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef HARDLINE_SCREENCAST_PIPEWIRE_CAPTURE_H_
#define HARDLINE_SCREENCAST_PIPEWIRE_CAPTURE_H_

#include <pipewire/pipewire.h>
#include <spa/param/video/format-utils.h>

#include <chrono>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "egl_dmabuf.h"
#include "i420.h"
#include "rtc_video_frame.h"
#include "rtc_video_source.h"

namespace hardline_screencast {

// Receives one screencast stream from PipeWire and feeds it into a WebRTC
// video source.
//
// The stream comes from the xdg-desktop-portal: the portal hands over a
// PipeWire remote (a file descriptor) and the node id of the stream the user
// picked. Frames arrive on PipeWire's own thread, in shared memory or as
// DMA-BUFs; both are converted to I420 there and pushed into the source.
class PipeWireCapture {
 public:
  // Called on the PipeWire thread when the stream ends on its own: the
  // compositor stopped it, or the PipeWire connection broke.
  using EndedCallback = std::function<void()>;

  PipeWireCapture(libwebrtc::scoped_refptr<libwebrtc::RTCVideoSource> source,
                  EndedCallback on_ended);
  ~PipeWireCapture();

  PipeWireCapture(const PipeWireCapture&) = delete;
  PipeWireCapture& operator=(const PipeWireCapture&) = delete;

  // Takes ownership of `fd`.
  bool Start(int fd, uint32_t node_id, std::string* error);

 private:
  static void OnStateChanged(void* data, pw_stream_state old,
                             pw_stream_state state, const char* error);
  static void OnParamChanged(void* data, uint32_t id, const spa_pod* param);
  static void OnProcess(void* data);
  static void OnCoreError(void* data, uint32_t id, int seq, int res,
                          const char* message);
  static void OnRenegotiate(void* data, uint64_t count);
  static void OnRepeatTimer(void* data, uint64_t expirations);
  static void OnThrottleTimer(void* data, uint64_t expirations);
  static void OnRemoveBuffer(void* data, pw_buffer* buffer);

  // EnumFormat params: every format with the importable modifiers first (GPU
  // buffers), then every format without (shared memory).
  std::vector<const spa_pod*> BuildFormats(spa_pod_builder* builder);
  void HandleFrame(spa_buffer* buffer);
  void ReleaseHeld();
  void PushFrame();
  void NotifyEnded();

  libwebrtc::scoped_refptr<libwebrtc::RTCVideoSource> source_;
  EndedCallback on_ended_;
  bool ended_ = false;

  pw_thread_loop* loop_ = nullptr;
  pw_context* context_ = nullptr;
  pw_core* core_ = nullptr;
  pw_stream* stream_ = nullptr;
  spa_hook core_listener_{};
  spa_hook stream_listener_{};
  spa_source* renegotiate_ = nullptr;
  spa_source* repeat_timer_ = nullptr;
  spa_source* throttle_timer_ = nullptr;
  // A frame that arrived too soon after the last, waiting for its turn.
  pw_buffer* held_ = nullptr;

  std::unique_ptr<EglDmaBuf> egl_;
  // Modifiers still believed importable, per SPA video format.
  std::vector<std::pair<uint32_t, std::vector<uint64_t>>> modifiers_;

  // The negotiated format.
  spa_video_info_raw format_{};
  bool dmabuf_ = false;

  std::vector<uint8_t> rgba_;
  I420Picture picture_;
  libwebrtc::scoped_refptr<libwebrtc::RTCVideoFrame> last_frame_;
  std::chrono::steady_clock::time_point last_push_{};
};

}  // namespace hardline_screencast

#endif  // HARDLINE_SCREENCAST_PIPEWIRE_CAPTURE_H_

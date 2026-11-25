// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "pipewire_capture.h"

#include <fcntl.h>
#include <spa/param/buffers.h>
#include <spa/param/video/raw-utils.h>
#include <spa/pod/builder.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <mutex>

namespace hardline_screencast {

namespace {

// Thirty frames a second at most; see OnProcess.
constexpr auto kMinFrameInterval = std::chrono::milliseconds(33);

constexpr uint32_t Fourcc(char a, char b, char c, char d) {
  return static_cast<uint32_t>(a) | (static_cast<uint32_t>(b) << 8) |
         (static_cast<uint32_t>(c) << 16) | (static_cast<uint32_t>(d) << 24);
}

// The packed 32-bit formats a compositor shares a screen in, in order of
// preference. PipeWire names them by byte order in memory; DRM by the bits of
// a little-endian word, hence the apparent reversal.
struct FormatInfo {
  spa_video_format spa;
  uint32_t drm;
  PixelLayout layout;
};

const FormatInfo kFormats[] = {
    {SPA_VIDEO_FORMAT_BGRx, Fourcc('X', 'R', '2', '4'), {2, 1, 0}},
    {SPA_VIDEO_FORMAT_BGRA, Fourcc('A', 'R', '2', '4'), {2, 1, 0}},
    {SPA_VIDEO_FORMAT_RGBx, Fourcc('X', 'B', '2', '4'), {0, 1, 2}},
    {SPA_VIDEO_FORMAT_RGBA, Fourcc('A', 'B', '2', '4'), {0, 1, 2}},
};

const FormatInfo* FindFormat(uint32_t spa) {
  for (const auto& format : kFormats) {
    if (format.spa == spa) return &format;
  }
  return nullptr;
}

const spa_pod* BuildFormat(spa_pod_builder* builder, uint32_t format,
                           const std::vector<uint64_t>* modifiers) {
  spa_rectangle size_default{1920, 1080};
  spa_rectangle size_min{1, 1};
  spa_rectangle size_max{16384, 16384};
  // Thirty frames a second at most: a screen share is text and windows, and
  // every frame is converted on the CPU. 0/1 lets the compositor send frames
  // only when something changed.
  spa_fraction rate_default{30, 1};
  spa_fraction rate_min{0, 1};
  spa_fraction rate_max{30, 1};

  spa_pod_frame frames[2];
  spa_pod_builder_push_object(builder, &frames[0], SPA_TYPE_OBJECT_Format,
                              SPA_PARAM_EnumFormat);
  spa_pod_builder_add(builder, SPA_FORMAT_mediaType,
                      SPA_POD_Id(SPA_MEDIA_TYPE_video), 0);
  spa_pod_builder_add(builder, SPA_FORMAT_mediaSubtype,
                      SPA_POD_Id(SPA_MEDIA_SUBTYPE_raw), 0);
  spa_pod_builder_add(builder, SPA_FORMAT_VIDEO_format, SPA_POD_Id(format), 0);
  if (modifiers != nullptr && !modifiers->empty()) {
    spa_pod_builder_prop(
        builder, SPA_FORMAT_VIDEO_modifier,
        SPA_POD_PROP_FLAG_MANDATORY | SPA_POD_PROP_FLAG_DONT_FIXATE);
    spa_pod_builder_push_choice(builder, &frames[1], SPA_CHOICE_Enum, 0);
    // An enum choice starts with its default value.
    spa_pod_builder_long(builder, static_cast<int64_t>((*modifiers)[0]));
    for (uint64_t modifier : *modifiers) {
      spa_pod_builder_long(builder, static_cast<int64_t>(modifier));
    }
    spa_pod_builder_pop(builder, &frames[1]);
  }
  spa_pod_builder_add(
      builder, SPA_FORMAT_VIDEO_size,
      SPA_POD_CHOICE_RANGE_Rectangle(&size_default, &size_min, &size_max), 0);
  spa_pod_builder_add(
      builder, SPA_FORMAT_VIDEO_framerate,
      SPA_POD_CHOICE_RANGE_Fraction(&rate_default, &rate_min, &rate_max), 0);
  return static_cast<const spa_pod*>(
      spa_pod_builder_pop(builder, &frames[0]));
}

void EnsurePipeWireInit() {
  static std::once_flag once;
  std::call_once(once, [] { pw_init(nullptr, nullptr); });
}

}  // namespace

PipeWireCapture::PipeWireCapture(
    libwebrtc::scoped_refptr<libwebrtc::RTCVideoSource> source,
    EndedCallback on_ended)
    : source_(source), on_ended_(std::move(on_ended)) {}

PipeWireCapture::~PipeWireCapture() {
  if (loop_ != nullptr) {
    pw_thread_loop_lock(loop_);
    if (stream_ != nullptr) {
      spa_hook_remove(&stream_listener_);
      pw_stream_disconnect(stream_);
      pw_stream_destroy(stream_);
      stream_ = nullptr;
    }
    if (core_ != nullptr) {
      spa_hook_remove(&core_listener_);
      pw_core_disconnect(core_);
      core_ = nullptr;
    }
    pw_loop* loop = pw_thread_loop_get_loop(loop_);
    if (renegotiate_ != nullptr) pw_loop_destroy_source(loop, renegotiate_);
    if (repeat_timer_ != nullptr) pw_loop_destroy_source(loop, repeat_timer_);
    if (throttle_timer_ != nullptr) {
      pw_loop_destroy_source(loop, throttle_timer_);
    }
    pw_thread_loop_unlock(loop_);
    pw_thread_loop_stop(loop_);
  }
  if (context_ != nullptr) pw_context_destroy(context_);
  if (loop_ != nullptr) pw_thread_loop_destroy(loop_);
  // The EGL context was released after the last frame, so it can be torn
  // down from this thread now that the capture thread has stopped.
  egl_.reset();
}

bool PipeWireCapture::Start(int fd, uint32_t node_id, std::string* error) {
  EnsurePipeWireInit();

  egl_ = std::make_unique<EglDmaBuf>();
  if (egl_->ok()) {
    for (const auto& format : kFormats) {
      auto modifiers = egl_->QueryModifiers(format.drm);
      if (!modifiers.empty()) modifiers_.push_back({format.spa, modifiers});
    }
  }

  loop_ = pw_thread_loop_new("hardline-screencast", nullptr);
  if (loop_ == nullptr) {
    close(fd);
    *error = "could not create the PipeWire loop";
    return false;
  }
  context_ = pw_context_new(pw_thread_loop_get_loop(loop_), nullptr, 0);
  if (context_ == nullptr || pw_thread_loop_start(loop_) < 0) {
    close(fd);
    *error = "could not start the PipeWire loop";
    return false;
  }

  pw_thread_loop_lock(loop_);

  core_ = pw_context_connect_fd(context_, fd, nullptr, 0);
  if (core_ == nullptr) {
    pw_thread_loop_unlock(loop_);
    *error = "could not connect to the screencast PipeWire remote";
    return false;
  }
  static pw_core_events core_events = [] {
    pw_core_events events{};
    events.version = PW_VERSION_CORE_EVENTS;
    events.error = &PipeWireCapture::OnCoreError;
    return events;
  }();
  pw_core_add_listener(core_, &core_listener_, &core_events, this);

  pw_loop* loop = pw_thread_loop_get_loop(loop_);
  renegotiate_ = pw_loop_add_event(loop, &PipeWireCapture::OnRenegotiate, this);
  repeat_timer_ =
      pw_loop_add_timer(loop, &PipeWireCapture::OnRepeatTimer, this);
  throttle_timer_ =
      pw_loop_add_timer(loop, &PipeWireCapture::OnThrottleTimer, this);
  timespec interval{0, 500 * 1000 * 1000};
  pw_loop_update_timer(loop, repeat_timer_, &interval, &interval, false);

  stream_ = pw_stream_new(
      core_, "Hardline screen share",
      pw_properties_new(PW_KEY_MEDIA_TYPE, "Video", PW_KEY_MEDIA_CATEGORY,
                        "Capture", PW_KEY_MEDIA_ROLE, "Screen", nullptr));
  if (stream_ == nullptr) {
    pw_thread_loop_unlock(loop_);
    *error = "could not create the PipeWire stream";
    return false;
  }
  static pw_stream_events stream_events = [] {
    pw_stream_events events{};
    events.version = PW_VERSION_STREAM_EVENTS;
    events.state_changed = &PipeWireCapture::OnStateChanged;
    events.param_changed = &PipeWireCapture::OnParamChanged;
    events.process = &PipeWireCapture::OnProcess;
    events.remove_buffer = &PipeWireCapture::OnRemoveBuffer;
    return events;
  }();
  pw_stream_add_listener(stream_, &stream_listener_, &stream_events, this);

  uint8_t buffer[16384];
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
  auto params = BuildFormats(&builder);
  const int result = pw_stream_connect(
      stream_, PW_DIRECTION_INPUT, node_id,
      static_cast<pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT |
                                   PW_STREAM_FLAG_MAP_BUFFERS),
      params.data(), params.size());
  pw_thread_loop_unlock(loop_);

  if (result < 0) {
    *error = "could not connect the PipeWire stream";
    return false;
  }
  return true;
}

std::vector<const spa_pod*> PipeWireCapture::BuildFormats(
    spa_pod_builder* builder) {
  std::vector<const spa_pod*> params;
  for (const auto& entry : modifiers_) {
    if (entry.second.empty()) continue;
    params.push_back(BuildFormat(builder, entry.first, &entry.second));
  }
  for (const auto& format : kFormats) {
    params.push_back(BuildFormat(builder, format.spa, nullptr));
  }
  return params;
}

void PipeWireCapture::OnStateChanged(void* data, pw_stream_state old,
                                     pw_stream_state state,
                                     const char* error) {
  auto* self = static_cast<PipeWireCapture*>(data);
  fprintf(stderr, "[screencast] stream %s -> %s%s%s\n",
          pw_stream_state_as_string(old), pw_stream_state_as_string(state),
          error ? ": " : "", error ? error : "");
  if (state == PW_STREAM_STATE_ERROR ||
      (state == PW_STREAM_STATE_UNCONNECTED &&
       old != PW_STREAM_STATE_UNCONNECTED)) {
    self->NotifyEnded();
  }
}

void PipeWireCapture::OnCoreError(void* data, uint32_t id, int seq, int res,
                                  const char* message) {
  auto* self = static_cast<PipeWireCapture*>(data);
  fprintf(stderr, "[screencast] PipeWire error on %u: %s\n", id,
          message ? message : "");
  if (id == PW_ID_CORE) self->NotifyEnded();
}

void PipeWireCapture::OnParamChanged(void* data, uint32_t id,
                                     const spa_pod* param) {
  auto* self = static_cast<PipeWireCapture*>(data);
  if (param == nullptr || id != SPA_PARAM_Format) return;

  spa_video_info_raw info{};
  if (spa_format_video_raw_parse(param, &info) < 0) return;
  self->format_ = info;
  // A modifier in the agreed format means the compositor sends GPU buffers.
  self->dmabuf_ =
      spa_pod_find_prop(param, nullptr, SPA_FORMAT_VIDEO_modifier) != nullptr;
  fprintf(stderr, "[screencast] format %u %ux%u, %s, modifier 0x%llx\n",
          static_cast<unsigned>(info.format),
          info.size.width, info.size.height,
          self->dmabuf_ ? "DMA-BUF" : "shared memory",
          static_cast<unsigned long long>(info.modifier));

  const int data_types =
      self->dmabuf_ ? (1 << SPA_DATA_DmaBuf)
                    : ((1 << SPA_DATA_MemFd) | (1 << SPA_DATA_MemPtr));
  uint8_t buffer[1024];
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
  const spa_pod* params[2];
  params[0] = static_cast<const spa_pod*>(spa_pod_builder_add_object(
      &builder, SPA_TYPE_OBJECT_ParamBuffers, SPA_PARAM_Buffers,
      SPA_PARAM_BUFFERS_buffers, SPA_POD_CHOICE_RANGE_Int(8, 1, 32),
      SPA_PARAM_BUFFERS_dataType, SPA_POD_CHOICE_FLAGS_Int(data_types)));
  params[1] = static_cast<const spa_pod*>(spa_pod_builder_add_object(
      &builder, SPA_TYPE_OBJECT_ParamMeta, SPA_PARAM_Meta, SPA_PARAM_META_type,
      SPA_POD_Id(SPA_META_Header), SPA_PARAM_META_size,
      SPA_POD_Int(sizeof(spa_meta_header))));
  pw_stream_update_params(self->stream_, params, 2);
}

void PipeWireCapture::OnProcess(void* data) {
  auto* self = static_cast<PipeWireCapture*>(data);
  // Only the newest frame matters; anything older that queued up while the
  // last one was being converted is handed straight back.
  pw_buffer* newest = nullptr;
  while (pw_buffer* next = pw_stream_dequeue_buffer(self->stream_)) {
    if (newest != nullptr) pw_stream_queue_buffer(self->stream_, newest);
    newest = next;
  }
  if (newest == nullptr) return;

  // Compositors send a frame per repaint whatever framerate was agreed (niri
  // sent 60 a second in testing), and each one costs a GPU readback and a
  // conversion of several megapixels. A frame that comes too soon is held
  // back rather than dropped: it may be the last one before the screen goes
  // still, and dropping it would leave the others looking at a stale picture.
  const auto now = std::chrono::steady_clock::now();
  const auto due = self->last_push_ + kMinFrameInterval;
  if (now < due) {
    if (self->held_ != nullptr) {
      pw_stream_queue_buffer(self->stream_, self->held_);
    }
    self->held_ = newest;
    const auto wait =
        std::chrono::duration_cast<std::chrono::nanoseconds>(due - now);
    timespec value{0, static_cast<long>(wait.count())};
    pw_loop_update_timer(pw_thread_loop_get_loop(self->loop_),
                         self->throttle_timer_, &value, nullptr, false);
    return;
  }
  self->ReleaseHeld();
  self->HandleFrame(newest->buffer);
  pw_stream_queue_buffer(self->stream_, newest);
}

void PipeWireCapture::ReleaseHeld() {
  if (held_ == nullptr) return;
  pw_stream_queue_buffer(stream_, held_);
  held_ = nullptr;
}

void PipeWireCapture::OnThrottleTimer(void* data, uint64_t expirations) {
  auto* self = static_cast<PipeWireCapture*>(data);
  pw_buffer* held = self->held_;
  if (held == nullptr || self->stream_ == nullptr) return;
  self->held_ = nullptr;
  self->HandleFrame(held->buffer);
  pw_stream_queue_buffer(self->stream_, held);
}

void PipeWireCapture::OnRemoveBuffer(void* data, pw_buffer* buffer) {
  // Buffers go away when the format is renegotiated.
  auto* self = static_cast<PipeWireCapture*>(data);
  if (self->held_ == buffer) self->held_ = nullptr;
}

void PipeWireCapture::HandleFrame(spa_buffer* buffer) {
  auto* header = static_cast<spa_meta_header*>(
      spa_buffer_find_meta_data(buffer, SPA_META_Header, sizeof(spa_meta_header)));
  if (header != nullptr && (header->flags & SPA_META_HEADER_FLAG_CORRUPTED)) {
    return;
  }
  if (buffer->n_datas < 1) return;

  const FormatInfo* format = FindFormat(format_.format);
  const int width = static_cast<int>(format_.size.width);
  const int height = static_cast<int>(format_.size.height);
  if (format == nullptr || width <= 0 || height <= 0) return;

  spa_data& first = buffer->datas[0];
  if (first.type == SPA_DATA_DmaBuf) {
    std::vector<DmaBufPlane> planes;
    for (uint32_t i = 0; i < buffer->n_datas; i++) {
      const spa_data& plane = buffer->datas[i];
      planes.push_back({static_cast<int>(plane.fd), plane.chunk->offset,
                        static_cast<uint32_t>(plane.chunk->stride)});
    }
    if (!egl_ || !egl_->ReadPixels(format->drm, format_.modifier, width,
                                   height, planes, &rgba_)) {
      // The GPU cannot read this layout after all. Stop offering the
      // modifier and let the compositor pick again; with none left for this
      // format it falls back to another format or to shared memory.
      for (auto& entry : modifiers_) {
        if (entry.first != format_.format) continue;
        auto& list = entry.second;
        list.erase(std::remove(list.begin(), list.end(), format_.modifier),
                   list.end());
      }
      pw_loop_signal_event(pw_thread_loop_get_loop(loop_), renegotiate_);
      return;
    }
    ConvertToI420(rgba_.data(), width * 4, width, height, {0, 1, 2},
                  &picture_);
  } else if (first.type == SPA_DATA_MemFd || first.type == SPA_DATA_MemPtr) {
    if (first.data == nullptr || first.chunk->size == 0) return;
    const int stride = first.chunk->stride > 0 ? first.chunk->stride : width * 4;
    const auto* pixels =
        static_cast<const uint8_t*>(first.data) + first.chunk->offset;
    if (static_cast<uint64_t>(stride) * (height - 1) + width * 4 +
            first.chunk->offset >
        first.maxsize) {
      return;
    }
    ConvertToI420(pixels, stride, width, height, format->layout, &picture_);
  } else {
    return;
  }

  last_frame_ = libwebrtc::RTCVideoFrame::Create(
      picture_.width, picture_.height, picture_.y(), picture_.stride_y(),
      picture_.u(), picture_.stride_uv(), picture_.v(), picture_.stride_uv());
  PushFrame();
}

void PipeWireCapture::PushFrame() {
  if (last_frame_.get() == nullptr) return;
  source_->OnCapturedFrame(last_frame_);
  last_push_ = std::chrono::steady_clock::now();
}

void PipeWireCapture::OnRepeatTimer(void* data, uint64_t expirations) {
  auto* self = static_cast<PipeWireCapture*>(data);
  // A compositor sends a frame only when something on screen changed. A
  // still screen would then send nothing at all, and whoever joins late, or
  // loses a packet, would wait for a key frame until the next mouse move. So
  // the last picture is sent again about once a second.
  if (std::chrono::steady_clock::now() - self->last_push_ >
      std::chrono::milliseconds(900)) {
    self->PushFrame();
  }
}

void PipeWireCapture::OnRenegotiate(void* data, uint64_t count) {
  auto* self = static_cast<PipeWireCapture*>(data);
  if (self->stream_ == nullptr) return;
  uint8_t buffer[16384];
  spa_pod_builder builder = SPA_POD_BUILDER_INIT(buffer, sizeof(buffer));
  auto params = self->BuildFormats(&builder);
  pw_stream_update_params(self->stream_, params.data(), params.size());
}

void PipeWireCapture::NotifyEnded() {
  if (ended_) return;
  ended_ = true;
  if (on_ended_) on_ended_();
}

}  // namespace hardline_screencast

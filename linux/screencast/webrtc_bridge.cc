// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "webrtc_bridge.h"

#include <glib.h>

#include "flutter_webrtc.h"
#include "flutter_webrtc/flutter_web_r_t_c_plugin.h"
#include "rtc_mediaconstraints.h"
#include "rtc_peerconnection_factory.h"

namespace hardline_screencast {

namespace {

using flutter_webrtc_plugin::FlutterWebRTCBase;

// flutter_webrtc keeps its factory and its tables of local streams and tracks
// protected, for its own friend classes. A class derived from it may still
// name those members, and a pointer-to-member taken that way is an ordinary
// pointer-to-member of FlutterWebRTCBase. That is all this does: no layout is
// guessed, the compiler works it out from flutter_webrtc's own headers, which
// are the ones its plugin was built from in this same build.
//
// Only data members and virtual functions are reached this way. The plugin is
// built with hidden visibility, so none of its non-virtual functions are
// exported to link against.
struct Access : FlutterWebRTCBase {
  static constexpr auto factory = &Access::factory_;
  static constexpr auto local_streams = &Access::local_streams_;
  static constexpr auto local_tracks = &Access::local_tracks_;
};

std::string NewUuid() {
  gchar* uuid = g_uuid_string_random();
  std::string result(uuid);
  g_free(uuid);
  return result;
}

}  // namespace

bool CreateInjectedTrack(InjectedTrack* out, std::string* error) {
  flutter_webrtc_plugin::FlutterWebRTC* webrtc =
      flutter_webrtc_plugin_get_shared_instance();
  if (webrtc == nullptr) {
    *error = "flutter_webrtc is not loaded";
    return false;
  }
  FlutterWebRTCBase* base = webrtc;

  auto& factory = base->*Access::factory;
  if (factory.get() == nullptr) {
    // Created with the first peer connection. Sharing is only offered inside
    // a call, so this is a call that has not come up yet.
    *error = "WebRTC is not initialised yet";
    return false;
  }

  const std::string stream_id = NewUuid();
  const std::string track_id = NewUuid();

  auto source = factory->CreateCustomVideoSource(
      "hardline_wayland_screencast", libwebrtc::RTCMediaConstraints::Create());
  if (source.get() == nullptr) {
    *error = "could not create a video source";
    return false;
  }
  auto track = factory->CreateVideoTrack(source, track_id.c_str());
  auto stream = factory->CreateStream(stream_id.c_str());
  if (track.get() == nullptr || stream.get() == nullptr) {
    *error = "could not create the video track";
    return false;
  }
  stream->AddTrack(track);

  // The same two entries getDisplayMedia makes. From here on flutter_webrtc
  // owns them: disposing the stream or track on the Dart side removes them
  // again, as it would for its own capture.
  (base->*Access::local_tracks)[track_id] = track;
  (base->*Access::local_streams)[stream_id] = stream;

  out->stream_id = stream_id;
  out->track_id = track_id;
  out->source = source;
  return true;
}

}  // namespace hardline_screencast

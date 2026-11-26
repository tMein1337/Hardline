// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef HARDLINE_SCREENCAST_WEBRTC_BRIDGE_H_
#define HARDLINE_SCREENCAST_WEBRTC_BRIDGE_H_

#include <string>

#include "rtc_video_frame.h"
#include "rtc_video_source.h"

namespace hardline_screencast {

// A local video track that this process feeds frames into itself, registered
// with flutter_webrtc as if its own getDisplayMedia had made it. The Dart side
// then wraps `stream_id`/`track_id` in a MediaStream exactly as flutter_webrtc
// does with a getDisplayMedia answer, and LiveKit publishes it like any other
// screen share.
struct InjectedTrack {
  std::string stream_id;
  std::string track_id;
  libwebrtc::scoped_refptr<libwebrtc::RTCVideoSource> source;
};

// Creates the track inside flutter_webrtc's own peer connection factory, so it
// can be added to the call's peer connection. Call on the platform thread.
// Returns false with `error` set when flutter_webrtc has no factory yet (no
// call has been joined) or is not loaded at all.
bool CreateInjectedTrack(InjectedTrack* out, std::string* error);

}  // namespace hardline_screencast

#endif  // HARDLINE_SCREENCAST_WEBRTC_BRIDGE_H_

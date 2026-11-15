// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// The encodings to send back to an RTP sender to open or shut it.
///
/// Pulled out of [AudioLevelSampler] because it is the whole of the bug that
/// made the breakpoint do nothing, and because it is the only part of that path
/// which can be tested without a live peer connection.
///
/// **The gate had never once closed.** Measured from the other end of a call
/// (`integration_test/call_flow.dart`): with the gate on and the level well
/// below the breakpoint, the listener heard the room exactly as loudly as with
/// it off, while the sender's own statistics went on counting fifty packets a
/// second and reporting the encoding active. Two defects, one on each side of
/// the platform channel, each hiding the other:
///
///  * **flutter_webrtc before 1.6.3 never applied an encoding change** on
///    Windows or Linux. Its native `updateRtpParameters` set `active` on
///    *copies* of the encodings and never wrote them back, so
///    `set_parameters` was handed the parameters unchanged and reported
///    success. 1.6.3 writes them back ("fix(desktop): write encoding changes
///    back in RtpSender setParameters").
///  * **This function then asked for something the sender refuses.** It used
///    to hand back the sender's cached encodings with `active` flipped, and
///    those carry everything else too — `ssrc: 0`, `maxBitrate: 0`, a
///    `scaleResolutionDownBy` that means nothing for audio. While the native
///    side discarded the lot, that cost nothing. Once it applied them, WebRTC
///    rejected the change outright: `setParameters` returned false and the
///    gate reported itself unavailable.
///
/// So this sends **only what the gate is about**: one encoding per encoding
/// the sender has, carrying `active`, the `rid` that identifies it and the
/// priority it already had, and nothing else. The native side reads the sender's current parameters and
/// overwrites only the fields it is given, so everything the publisher
/// configured — bitrate, priority, the ssrc — stays exactly as it was.
///
/// When the sender reports no encodings at all, which an audio sender
/// routinely does from Dart, one is sent anyway: the native side zips the list
/// against its own and a single entry reaches the first real encoding, which
/// for a non-simulcast audio sender is the only one there is.
List<rtc.RTCRtpEncoding> gateEncodings(
  rtc.RTCRtpParameters parameters, {
  required bool open,
}) {
  final existing = parameters.encodings;
  if (existing == null || existing.isEmpty) return [_only(open: open)];
  return [
    for (final encoding in existing)
      _only(open: open, rid: encoding.rid, priority: encoding.priority),
  ];
}

/// An encoding carrying [open], [rid] and [priority], and nothing else.
///
/// The nulls are explicit because `RTCRtpEncoding` defaults two fields to
/// values — one temporal layer, no downscale — and `toMap` sends whatever is
/// not null. `priority` it sends always, so it is carried over from the
/// encoding being gated rather than left at the constructor's default, which
/// would quietly lower a sender the publisher had raised.
rtc.RTCRtpEncoding _only({
  required bool open,
  String? rid,
  rtc.RTCPriorityType priority = rtc.RTCPriorityType.low,
}) => rtc.RTCRtpEncoding(
  active: open,
  rid: rid,
  numTemporalLayers: null,
  scaleResolutionDownBy: null,
  priority: priority,
);

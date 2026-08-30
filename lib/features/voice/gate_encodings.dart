// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// The encodings to send back to an RTP sender to open or shut it.
///
/// Pulled out of [AudioLevelSampler] because it is the whole of the bug that
/// made the breakpoint do nothing, and because it is the only part of that path
/// which can be tested without a live peer connection.
///
/// **Why this is not just a loop over what the sender already has.** The gate
/// used to read `sender.parameters`, walk `parameters.encodings`, set `active`
/// on each, and hand the object back. Three things conspire to make that a
/// silent no-op on Windows:
///
///  * `RTCRtpSenderNative.parameters` returns a **cached field**, populated
///    once when the sender was built from the platform's map. For an audio
///    sender that map routinely carries no encodings at all.
///  * `for (final e in parameters.encodings ?? const [])` over an empty list
///    runs zero times, so the object goes back exactly as it came.
///  * The native side (`updateRtpParameters` in flutter_webrtc's
///    `flutter_peerconnection.cc`) zips the incoming list against the encodings
///    libwebrtc actually has and stops as soon as the incoming list runs out.
///    An empty list therefore sets nothing, and `set_parameters` still reports
///    success.
///
/// No exception, no failed result anybody looked at, and the meter cheerfully
/// reporting that nothing was being sent while the microphone transmitted the
/// whole time.
///
/// So: when the sender knows its encodings, reuse them and flip `active`. When
/// it does not, **synthesise one**. The native side zips against its own list,
/// so a single entry reaches the first real encoding, which for a
/// non-simulcast audio sender is the only one there is.
List<rtc.RTCRtpEncoding> gateEncodings(
  rtc.RTCRtpParameters parameters, {
  required bool open,
}) {
  final existing = parameters.encodings;
  if (existing == null || existing.isEmpty) {
    return [rtc.RTCRtpEncoding(active: open)];
  }
  for (final encoding in existing) {
    encoding.active = open;
  }
  return existing;
}

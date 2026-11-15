// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

/// Runs [body] with WebRTC's audio device module awake.
///
/// **The module lists no devices at all unless it is.** On Windows it is
/// initialised only while some peer connection carries an audio transceiver,
/// and shut down again when the last one goes. Before that, and after,
/// enumerating returns an empty list — not an error, not a default device,
/// nothing — and selecting a device selects into a module that is about to
/// forget it.
///
/// That made three things silently wrong, all of them measured by the call
/// suite in `integration_test/`:
///
///  * **The voice settings outside a call** showed no microphones and no
///    outputs, so a device could only be chosen while already in one.
///  * **Joining used the system default microphone**, whatever had been
///    chosen. The chosen one is resolved to a capture constraint just before
///    the microphone is published — which is exactly the moment no audio
///    transceiver exists yet, so the lookup found nothing and capture fell
///    back to the default.
///  * **The output chosen was lost on join** for the same reason.
///
/// A receive-only audio transceiver on a peer connection of its own is enough
/// to bring the module up, and it does so without opening any microphone: no
/// capture starts, nothing is sent, and the connection never leaves this
/// process. It is closed again as soon as [body] is done.
///
/// Cheap when it is not needed: if the module already lists devices — any
/// time a call is up — [body] simply runs.
Future<T> withAudioDevicesAwake<T>(Future<T> Function() body) async {
  if (_hasAudio(await lk.Hardware.instance.enumerateDevices())) {
    return body();
  }

  rtc.RTCPeerConnection? waker;
  try {
    waker = await rtc.createPeerConnection({});
    await waker.addTransceiver(
      kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: rtc.RTCRtpTransceiverInit(
        direction: rtc.TransceiverDirection.RecvOnly,
      ),
    );
  } catch (error) {
    // Nothing to wake with. The body still runs, and finds what it finds —
    // which on a platform without this behaviour is everything.
    debugPrint('[voice] could not wake the audio device module: $error');
  }

  try {
    return await body();
  } finally {
    await waker?.close();
    await waker?.dispose();
  }
}

/// Every audio input and output, listed with the module awake.
Future<({List<lk.MediaDevice> inputs, List<lk.MediaDevice> outputs})>
listAudioDevices() => withAudioDevicesAwake(() async {
  final devices = await lk.Hardware.instance.enumerateDevices();
  return (
    inputs: [
      for (final device in devices)
        if (device.kind == 'audioinput') device,
    ],
    outputs: [
      for (final device in devices)
        if (device.kind == 'audiooutput') device,
    ],
  );
});

bool _hasAudio(List<lk.MediaDevice> devices) => devices.any(
  (device) => device.kind == 'audioinput' || device.kind == 'audiooutput',
);

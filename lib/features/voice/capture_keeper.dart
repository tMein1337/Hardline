// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

/// Keeps the microphone being read while the gate holds the call's sender shut.
///
/// **WebRTC reads the microphone only while something is sending it.** The
/// audio device records while at least one audio send stream is running and
/// stops the moment the last one stops — and deactivating a sender's encoding,
/// which is how the gate shuts, stops its stream. With the call's sender the
/// only one in the process, closing the gate therefore stopped the recording,
/// the tap the gate listens through went dark with it, and nothing could ever
/// open the gate again. Measured (`integration_test/zz_probe` at the time): the
/// tap delivered a hundred readings a second with the sender active and none
/// at all with it inactive — on every track from that microphone, not only
/// the published one.
///
/// The two-person call test had not caught it, because its second person runs
/// in the same process and their sender kept the device recording for both.
///
/// So while the gate is in charge, this holds a second sender of the same
/// track open on a connection to itself: two peer connections in this process,
/// joined over loopback, nothing leaving the machine. Its stream keeps the
/// device recording; the receiving end's track is disabled, so what it decodes
/// is never played. It costs one Opus encoder and decoder for as long as the
/// gate is on — a fraction of a percent of one core.
///
/// A sender that is negotiated but never connected is not enough: it was tried,
/// and the recording stopped all the same. The connection has to come up.
class CaptureKeeper {
  rtc.RTCPeerConnection? _out;
  rtc.RTCPeerConnection? _in;
  String? _trackId;
  Future<bool>? _starting;

  /// Whether [track] is being kept read.
  bool isKeeping(rtc.MediaStreamTrack track) =>
      _trackId == track.id && _out != null;

  /// Starts keeping [track] read, and completes once that is certain.
  ///
  /// Returns false if the loopback did not come up. The caller must then not
  /// shut its sender: a gate that closes without this closes for good.
  Future<bool> keep(rtc.MediaStreamTrack track) {
    if (isKeeping(track)) return Future.value(true);
    final starting = _starting;
    if (starting != null && _trackId == track.id) return starting;
    return _starting = _start(track).whenComplete(() => _starting = null);
  }

  Future<bool> _start(rtc.MediaStreamTrack track) async {
    await release();
    _trackId = track.id;
    rtc.RTCPeerConnection? out;
    rtc.RTCPeerConnection? into;
    try {
      // No ICE servers: host candidates on this machine are all it needs.
      out = await rtc.createPeerConnection({'iceServers': <Object>[]});
      into = await rtc.createPeerConnection({'iceServers': <Object>[]});
      final a = out;
      final b = into;
      a.onIceCandidate = (candidate) => unawaited(b.addCandidate(candidate));
      b.onIceCandidate = (candidate) => unawaited(a.addCandidate(candidate));
      // Never played: the receiving end exists only so the sender has
      // somewhere to send.
      b.onTrack = (event) => event.track.enabled = false;

      final connected = Completer<bool>();
      a.onConnectionState = (state) {
        if (connected.isCompleted) return;
        if (state ==
            rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          connected.complete(true);
        } else if (state ==
            rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          connected.complete(false);
        }
      };

      await a.addTransceiver(
        track: track,
        kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: rtc.RTCRtpTransceiverInit(
          direction: rtc.TransceiverDirection.SendOnly,
        ),
      );
      final offer = await a.createOffer();
      await a.setLocalDescription(offer);
      // The receiving end is told the track by another name. The plugin
      // finds tracks by id alone, and the id travels in the SDP: unrenamed,
      // the received copy shares the call's microphone track's id, and
      // disabling the copy disables the microphone — which is what happened,
      // and the call went silent the first time the keeper was released.
      await b.setRemoteDescription(
        rtc.RTCSessionDescription(
          offer.sdp?.replaceAll(track.id!, 'capture-keeper-${track.id}'),
          offer.type,
        ),
      );
      final answer = await b.createAnswer();
      await b.setLocalDescription(answer);
      await a.setRemoteDescription(answer);

      final up = await connected.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      if (!up || _trackId != track.id) {
        debugPrint('[voice] the capture keeper did not connect');
        await _close(out, into);
        if (_trackId == track.id) _trackId = null;
        return false;
      }
      _out = out;
      _in = into;
      debugPrint('[voice] capture keeper holding the microphone open');
      return true;
    } catch (error, stack) {
      debugPrint('[voice] the capture keeper failed: $error\n$stack');
      await _close(out, into);
      if (_trackId == track.id) _trackId = null;
      return false;
    }
  }

  /// Stops keeping anything read. The call's own sender, if active, goes on
  /// recording by itself.
  Future<void> release() async {
    final out = _out;
    final into = _in;
    _out = null;
    _in = null;
    _trackId = null;
    await _close(out, into);
  }

  static Future<void> _close(
    rtc.RTCPeerConnection? out,
    rtc.RTCPeerConnection? into,
  ) async {
    for (final connection in [out, into]) {
      if (connection == null) continue;
      try {
        await connection.close();
        await connection.dispose();
      } catch (error) {
        debugPrint('[voice] closing the capture keeper failed: $error');
      }
    }
  }
}

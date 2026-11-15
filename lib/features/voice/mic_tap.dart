// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

/// Reads the microphone **before** the gate touches it.
///
/// The gate shuts the microphone by disabling the capture track. Anything that
/// measures the same track downstream of that flag is measuring the gate's own
/// handiwork: a closed gate would read silence, conclude the room is quiet, and
/// never reopen. The way out is the ordinary one for any audio chain — tap the
/// signal upstream of the thing that attenuates it, and let the two paths
/// diverge from there.
///
/// LiveKit's `AudioVisualizer` is that tap. It attaches a sink directly to the
/// `RTCAudioTrack` (`AddSink`, in the plugin's native code), which is fed from
/// the capture source rather than from the send path, so it keeps delivering
/// whatever the microphone hears no matter what the published track is doing.
///
/// It is not free — a 2048-point FFT on every 10ms audio frame, pushed over an
/// event channel about a hundred times a second — but it runs natively and
/// only while a call is up. That is the price of a measurement the gate cannot
/// blind, and the alternative was a gate that might silently stop working.
///
/// ## Decibels, and where they come from
///
/// The visualizer does not hand back a level. It hands back frequency-band
/// magnitudes, already squashed by its own curve: `sqrt(1 - |dB| / 100)` over a
/// window clamped to -100..-30 dB. Many narrow bands are asked for and the
/// loudest is taken (see [bandCount] for why not one wide one), and that curve
/// is **undone** to recover the decibels before anything else sees it.
///
/// Everything downstream then works in dB, which is the unit the threshold is
/// stored and displayed in. That matters for more than tidiness: loudness is
/// logarithmic, so a control linear in amplitude spends most of its travel on
/// differences nobody can hear — and a number somebody can read off a meter and
/// type back in is worth far more than an abstract 0..1.
///
/// It is a *relative* reading rather than a calibrated one. The magnitude is
/// the strongest narrow FFT band between 10Hz and 8kHz, referenced to full
/// scale, so it behaves like dBFS and is repeatable on one microphone — which
/// is all a gate threshold needs — without being a measurement anybody should
/// quote.
class MicTap {
  /// What silence reads.
  ///
  /// The visualizer's own floor, so a band of zero lands exactly here. Used as
  /// the "nothing at all" value everywhere downstream.
  static const silenceDb = -100.0;

  /// The loudest reading that can be distinguished.
  ///
  /// The visualizer clamps its input at -30 dB, so everything above this is
  /// reported as this. The slider stops here for that reason and not by choice.
  static const ceilingDb = -30.0;

  lk.AudioVisualizer? _visualizer;
  lk.EventsListener<lk.AudioVisualizerEvent>? _listener;
  String? _trackId;

  double _peak = silenceDb;
  bool _delivered = false;

  /// Whether the tap has ever produced a reading.
  ///
  /// False means the native visualizer never started — an older plugin, an
  /// unsupported platform — and the gate must not act on a measurement it is
  /// not getting. The settings pane says so rather than showing a threshold
  /// that does nothing.
  bool get isLive => _delivered;

  /// Whether this tap is already listening to [track].
  bool isAttachedTo(lk.LocalAudioTrack track) =>
      _trackId != null && _trackId == track.mediaStreamTrack.id;

  /// The loudest reading in dB since the last call, and resets.
  ///
  /// A peak rather than the latest value, for the same reason the remote half
  /// reads cumulative counters: the tap delivers ten times faster than anything
  /// reads it, and sampling one instant in ten would miss the attack of a
  /// syllable — which is exactly the moment a gate has to open on.
  double takePeakDb() {
    final peak = _peak;
    _peak = silenceDb;
    return peak;
  }

  Future<void> attach(lk.LocalAudioTrack track) async {
    if (isAttachedTo(track)) return;
    await detach();

    // Claimed *before* starting, and kept even if starting fails. The caller
    // asks on every 100ms tick, so a tap that gave the track back on failure
    // would spend the whole call building and tearing down a native visualizer
    // ten times a second, logging as it went.
    _trackId = track.mediaStreamTrack.id;

    final visualizer = lk.createVisualizer(
      track,
      // Many narrow bands, of which the loudest is the reading — see
      // [bandCount]. Uncentred: the centring step sorts and mirrors the bands
      // for a symmetrical drawing, which is meaningless here.
      options: const lk.AudioVisualizerOptions(
        barCount: bandCount,
        centeredBands: false,
      ),
    );
    final listener = visualizer.createListener()
      ..on<lk.AudioVisualizerEvent>(_onBands);

    _visualizer = visualizer;
    _listener = listener;

    try {
      await visualizer.start();
      debugPrint('[voice] microphone tap started on $_trackId');
    } catch (error, stack) {
      // The track stays claimed, so this is said once rather than ten times a
      // second. `isLive` stays false and the sampler falls back to statistics.
      debugPrint('[voice] the microphone tap did not start: $error\n$stack');
      await _releaseVisualizer();
    }
  }

  /// Tears the native visualizer down without giving the track back.
  Future<void> _releaseVisualizer() async {
    final visualizer = _visualizer;
    final listener = _listener;
    _visualizer = null;
    _listener = null;

    try {
      await visualizer?.stop();
      await visualizer?.dispose();
      await listener?.dispose();
    } catch (error) {
      debugPrint('[voice] tearing down the microphone tap failed: $error');
    }
  }

  Future<void> detach() async {
    _trackId = null;
    _peak = silenceDb;
    _delivered = false;
    await _releaseVisualizer();
  }

  Future<void> dispose() => detach();

  void _onBands(lk.AudioVisualizerEvent event) {
    final db = loudestDb(event.event);
    if (db == null) return;

    if (!_delivered) {
      _delivered = true;
      debugPrint('[voice] microphone tap is delivering');
    }
    if (db > _peak) _peak = db;
  }

  /// How many bands the visualizer is asked for.
  ///
  /// It splits 10Hz–8kHz into this many and reports, for each, the *average
  /// of the decibels* of the FFT bins inside it. Averaging decibels is what
  /// makes a wide band useless as a level: the bins between a voice's
  /// harmonics are nearly empty, sit far down, and drag the mean with them.
  /// With **one** band — what this used to ask for — a held vowel read as
  /// quiet while the onset before it read loud, so the gate saw every
  /// syllable as a click followed by silence (`integration_test/call_flow.dart`:
  /// a word played at -14 dBFS was over the breakpoint for its first 100ms and
  /// under it for the rest, while the other end heard it loud throughout).
  /// It is also why the reading was "systematically low" and needed the trim.
  ///
  /// Sixty-four bands are about five bins, 120Hz, each — narrower than the
  /// spacing of a voice's harmonics, so a band holding one is dominated by
  /// it — and the loudest of them follows the strongest part of the sound,
  /// which is what a level is.
  static const bandCount = 64;

  /// The loudest band of one visualizer event, in dB, or null if it carried
  /// none.
  @visibleForTesting
  static double? loudestDb(List<Object?> bands) {
    double? loudest;
    for (final band in bands) {
      if (band is! num) continue;
      final db = decibelsOf(band.toDouble());
      if (loudest == null || db > loudest) loudest = db;
    }
    return loudest;
  }

  /// Undoes the visualizer's curve to recover decibels.
  ///
  /// Its output is `sqrt(1 - |dB| / 100)`, so squaring recovers the fraction
  /// and the decibels follow. Reconstructing rather than using the number as it
  /// arrives is what makes a dB slider possible at all: raw, the whole span
  /// between a quiet room and ordinary speech sits in the top fifth of a 0..1
  /// range, which is precisely where a threshold has to be placed.
  @visibleForTesting
  static double decibelsOf(double band) {
    final fraction = (band * band).clamp(0.0, 1.0);
    return (-(1 - fraction) * 100).clamp(silenceDb, ceilingDb);
  }

  /// The band value a given reading would have come from. Test-only inverse.
  @visibleForTesting
  static double bandForDecibels(double db) => math.sqrt(1 + db / 100);
}

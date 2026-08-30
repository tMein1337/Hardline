// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import 'gate_encodings.dart';
import 'mic_tap.dart';
import 'noise_gate.dart';

/// The gate's user-facing settings, read fresh on every tick.
@immutable
class GateSettings {
  const GateSettings({
    required this.enabled,
    required this.thresholdDb,
    required this.gainDb,
  });

  final bool enabled;

  /// On [MicTap]'s scale, so the number here is the number on the slider.
  final double thresholdDb;

  /// Added to the reading **before** the threshold is applied.
  ///
  /// Which is the only order that makes sense: the trim exists to move a quiet
  /// microphone into the part of the scale the threshold can work in, so a
  /// threshold compared against the untrimmed reading would be comparing
  /// against the very number the trim was there to fix.
  ///
  /// It does not touch the audio. See [AudioLevelSampler].
  final double gainDb;
}

/// Measures who is making sound, and gates the microphone.
///
/// Everything here exists because **LiveKit will not tell us either of these
/// things at a useful resolution.** The SFU decides who is "speaking" with a
/// threshold of its own that no client can reach, and reports it a couple of
/// times a second; that is what made the speaking ring only light up for
/// somebody talking loudly. Levels measured on this machine are the only
/// numbers we control.
///
/// The two halves are measured differently, and for different reasons:
///
///  * **Locally**, through [MicTap] — a sink on the capture track, upstream of
///    the gate. It has to be upstream: the gate works by disabling that track,
///    and anything reading it downstream would be measuring the gate's own
///    handiwork, see silence, and never reopen.
///  * **Remotely**, `inbound-rtp.totalAudioEnergy` over `totalSamplesDuration`
///    from the statistics. Both accumulate, so the RMS across a tick is the
///    square root of one delta divided by the other. Cumulative counters are
///    used rather than an instantaneous reading because they cannot miss a
///    burst *between* two polls — everything that arrived is in the total.
///
/// `media-source.audioLevel` would be the obvious local reading and is not the
/// first choice, for exactly the reason above: it is measured on the track the
/// gate mutes. It is kept as a fallback for builds where the tap never starts.
///
/// ## The trim is on the measurement, not on the audio
///
/// [GateSettings.gainDb] is added to the reading before the threshold sees it,
/// and changes nothing about how loud anybody sounds. It cannot: WebRTC exposes
/// no gain on a local capture source (`SetVolume` is playout gain, implemented
/// for remote sources only), and automatic gain control is already running.
///
/// It is needed because the reading is systematically low. The tap asks the
/// visualizer for **one** band spanning 10Hz to 8kHz and gets the average
/// magnitude across it, so speech energy — which lives between roughly 100Hz
/// and 4kHz — is divided among a majority of near-empty bins. Ordinary talking
/// on a dynamic microphone measures around -90 dB on this scale rather than the
/// -35 the same voice would show as a broadband level. Without a trim the whole
/// useful range is a few decibels above the floor.
///
/// If somebody is too quiet for *other people*, this is not the control for it
/// — that is the microphone's own level, in the operating system's sound
/// settings.
class AudioLevelSampler {
  AudioLevelSampler({
    required this.readGateSettings,
    required this.onMicLevel,
    required this.onAudible,
  });

  /// Read on every tick, so moving the slider takes effect immediately rather
  /// than at the start of the next call.
  final GateSettings Function() readGateSettings;

  final ValueChanged<MicLevel> onMicLevel;

  /// The LiveKit identities that are currently making a sound we can hear.
  final ValueChanged<Set<String>> onAudible;

  /// How often the microphone is measured.
  ///
  /// The gate's responsiveness is bounded by this: a word cannot open the gate
  /// faster than the next tick, so anything much slower clips the start of
  /// speech. 100ms costs one statistics call per tick and is not perceptible.
  static const _micInterval = Duration(milliseconds: 100);

  /// Remote levels are sampled every other tick.
  ///
  /// They only move a ring, so half the rate is plenty — and unlike the
  /// microphone, this cost is paid once *per participant*, so it is the half
  /// worth economising on in a busy call.
  static const _remoteEvery = 2;

  /// The level below which a received signal is treated as nothing.
  ///
  /// Deliberately almost zero. The requirement is that a ring appears for any
  /// audio at all, however quiet, so this is set only high enough to ignore
  /// the numerical dust that decoders emit during silence — about -80 dBFS,
  /// far below anything a person could hear.
  static const _audibleFloor = 1e-4;

  lk.Room? _room;
  Timer? _timer;
  int _tick = 0;
  bool _sampling = false;

  /// Decides whether the microphone is transmitting. Rebuilt whenever the
  /// breakpoint changes; null while the gate is switched off.
  NoiseGate? _liveGate;

  /// Decides whether the avatar rings, and runs whether the gate is on or not.
  ///
  /// A second state machine rather than a reading of the first, because they
  /// answer different questions. With the gate off, "is anything being
  /// withheld" is permanently no — wire a ring to that and it lights on the
  /// first sample of a call and stays lit for the rest of it. "Is this person
  /// over their breakpoint" has an answer either way.
  NoiseGate? _indicator;

  /// Last cumulative reading per remote track, for the delta.
  final Map<String, ({num energy, num duration})> _lastRemote = {};

  /// Whether the gate currently has the microphone shut.
  bool _muzzled = false;

  /// The sender [_muzzled] describes.
  ///
  /// Without this, the open/shut state is held against the sampler while the
  /// thing it describes is replaced underneath it — a device change, an ICE
  /// restart or a republish all hand out a fresh sender, which starts active.
  /// The early return in [_setMicrophoneOpen] would then decide there was
  /// nothing to do and leave the new sender open with the gate believing it
  /// shut.
  String? _muzzledSenderId;

  /// Whether the last attempt to shut the microphone was accepted.
  ///
  /// False once `setParameters` has reported failure. That answer is
  /// load-bearing: it is the difference between "the gate is holding your
  /// microphone shut" and "the gate asked and was ignored", and only one of
  /// those should be drawn as silence on the meter.
  bool _gateEffective = true;

  /// Reads the microphone upstream of the gate. See [MicTap].
  final _tap = MicTap();

  /// Begins measuring [room].
  ///
  /// **`stop()` must be awaited before the new room is set.** It is async — it
  /// detaches the tap and reopens the microphone — and its tail sets `_room` to
  /// null. Called without awaiting, that tail lands *after* this method has
  /// installed the new room and started the timer, and quietly wipes it: every
  /// tick then finds no track, reports nothing, and the meter sits on "join a
  /// call" for the whole call. Which is exactly what it did.
  Future<void> start(lk.Room room) async {
    await stop();
    _room = room;
    _timer = Timer.periodic(_micInterval, (_) => unawaited(_sample()));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _tick = 0;
    _lastRemote.clear();
    _liveGate?.reset();
    _liveGate = null;
    _indicator = null;
    await _tap.detach();

    // Never leave a call with the microphone shut by a gate that has stopped
    // running. The track outlives this object's interest in it.
    await _openMicrophone();

    _room = null;
    onMicLevel(const MicLevel.none());
    onAudible(const {});
  }

  Future<void> dispose() => stop();

  Future<void> _sample() async {
    // A tick that overruns must not stack on the next one: statistics calls
    // cross a platform channel and can be slower than the interval under load.
    if (_sampling) return;
    _sampling = true;
    try {
      await _sampleMicrophone();
      if (_tick % _remoteEvery == 0) await _sampleRemotes();
      _tick++;
    } catch (error, stack) {
      debugPrint('[voice] audio level sampling failed: $error\n$stack');
    } finally {
      _sampling = false;
    }
  }

  Future<void> _sampleMicrophone() async {
    final track = _localTrack();
    final settings = readGateSettings();
    final now = DateTime.now();

    if (track == null) {
      _liveGate = null;
      _indicator = null;
      _muzzled = false;
      _muzzledSenderId = null;
      _gateEffective = true;
      onMicLevel(const MicLevel.none());
      return;
    }

    // A track the user has muted is not a track the gate has anything to say
    // about, and reading a level off it would only produce a meter twitching
    // at zero.
    if (track.muted) {
      onMicLevel(const MicLevel.none());
      return;
    }

    await _tap.attach(track);

    // The tap is preferred, but it is native code we do not control and it can
    // simply not be there. Statistics are the fallback, and they are a perfectly
    // good reading *while the gate is open* — which, since the gate ships off,
    // is the case for anybody who has not turned it on. Falling back is what
    // keeps the meter alive on a build where the tap never starts, instead of
    // showing an empty bar with no explanation.
    final tapped = _tap.isLive;
    final raw = tapped ? _tap.takePeakDb() : await _statsDb(track);

    if (raw == null) {
      onMicLevel(const MicLevel.none());
      return;
    }

    // Trim first, threshold second. Everything downstream — the gate, the
    // meter, the speaking ring — works on the trimmed value, so the number a
    // person reads off the meter is the number they set the threshold to.
    //
    // **Silence is not trimmed.** There is nothing to amplify in nothing, and
    // keeping the floor at the floor is what makes the meter honest: a bar
    // sitting at the very bottom says "no signal at all", which is the reading
    // somebody needs in order to tell a dead microphone from a quiet room.
    // Lifting it by the trim would put a +40 dB floor at -60 and make the two
    // indistinguishable.
    final db = raw <= MicTap.silenceDb
        ? MicTap.silenceDb
        : (raw + settings.gainDb).clamp(MicTap.silenceDb, MicTap.ceilingDb);

    // The gate is only allowed to run on the tap. Driving it from statistics
    // would mean measuring the very track it disables: it would read silence,
    // conclude the room was quiet, and never reopen — leaving somebody
    // inaudible with nothing on screen to say so. That is why the gate refuses
    // to switch on without the tap rather than falling back.
    // Answered on every tick, gate or no gate: it is what lights the avatar,
    // and the avatar is not a report on whether audio is being withheld.
    final speaking = _indicatorFor(settings.thresholdDb).update(db, now);

    if (!settings.enabled || !tapped) {
      _liveGate = null;
      _gateEffective = true;
      await _openMicrophone();
      onMicLevel(
        MicLevel(
          db: db,
          speaking: speaking,
          // Nothing is being withheld, so everything is going out.
          gateOpen: true,
          gateActive: false,
          gateAvailable: tapped,
        ),
      );
      return;
    }

    // Rebuilt when the breakpoint moves, because it is final on the gate — a
    // running state machine whose breakpoint changed underneath it would be
    // reasoning about two different questions at once.
    final gate = _liveGate?.thresholdDb == settings.thresholdDb
        ? _liveGate!
        : (_liveGate = NoiseGate(thresholdDb: settings.thresholdDb));

    final open = gate.update(db, now);
    await _setMicrophoneOpen(open);

    onMicLevel(
      MicLevel(
        db: db,
        speaking: speaking,
        // What is actually happening, not what was asked for. If the sender
        // refused the change the microphone is open however shut the gate
        // believes itself to be, and the meter must not claim otherwise.
        gateOpen: _gateEffective ? open : true,
        gateActive: _gateEffective,
        gateAvailable: _gateEffective,
      ),
    );
  }

  /// The state machine behind the avatar ring.
  ///
  /// Same hold as the gate, so the ring does not strobe on the gaps inside a
  /// sentence. A second instance rather than a reading of the first, because
  /// they answer different questions: this one says whether somebody is
  /// talking, and runs whether the gate is switched on or not.
  NoiseGate _indicatorFor(double thresholdDb) =>
      _indicator?.thresholdDb == thresholdDb
      ? _indicator!
      : (_indicator = NoiseGate(thresholdDb: thresholdDb));

  /// The microphone level in dB, from WebRTC's statistics.
  ///
  /// The fallback when the tap is not delivering. `media-source.audioLevel` is
  /// a linear 0..1 amplitude, so it becomes decibels the ordinary way and lands
  /// on the same scale the tap reports — a threshold means roughly the same
  /// thing either way. Roughly, and not exactly: one is an FFT band magnitude
  /// and the other a full-band amplitude, so the two are not calibrated
  /// against each other.
  Future<double?> _statsDb(lk.LocalAudioTrack track) async {
    final stats = await track.getSenderStats();
    final amplitude = stats?.audioSourceStats?.audioLevel;
    if (amplitude == null) return null;
    if (amplitude <= 0) return MicTap.silenceDb;
    return (20 * (math.log(amplitude) / math.ln10)).clamp(
      MicTap.silenceDb,
      MicTap.ceilingDb,
    );
  }

  Future<void> _sampleRemotes() async {
    final room = _room;
    if (room == null) return;

    final audible = <String>{};
    final seen = <String>{};

    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        final track = publication.track;
        if (track is! lk.RemoteAudioTrack) continue;

        final key = '${participant.identity}|${publication.sid}';
        seen.add(key);

        final stats = await track.getReceiverStats();
        final energy = stats?.totalAudioEnergy;
        final duration = stats?.totalSamplesDuration;
        if (energy == null || duration == null) continue;

        final previous = _lastRemote[key];
        _lastRemote[key] = (energy: energy, duration: duration);
        if (previous == null) continue;

        final samples = duration - previous.duration;
        if (samples <= 0) continue;

        // RMS over the interval. The counters are cumulative, so this is the
        // average level of everything that arrived since the last look —
        // nothing can slip between two polls.
        final rms = math.sqrt((energy - previous.energy) / samples);
        if (rms > _audibleFloor) audible.add(participant.identity);
      }
    }

    _lastRemote.removeWhere((key, _) => !seen.contains(key));
    onAudible(audible);
  }

  lk.LocalAudioTrack? _localTrack() {
    final publications = _room?.localParticipant?.trackPublications.values;
    if (publications == null) return null;

    lk.LocalAudioTrack? found;
    for (final publication in publications) {
      // Screen-share audio is also a local audio track, and gating it would be
      // a strange thing to do to somebody's shared video.
      if (publication.source == lk.TrackSource.screenShareAudio) continue;
      final track = publication.track;
      if (track is! lk.LocalAudioTrack) continue;
      // Prefer one that says it is the microphone, but take any other audio
      // track rather than none: `source` is set by whoever published, and a
      // reading from the wrong-but-only track beats no meter at all.
      if (publication.source == lk.TrackSource.microphone) return track;
      found ??= track;
    }
    return found;
  }

  /// Opens or shuts the microphone without telling anybody.
  ///
  /// `mediaStreamTrack.enabled`, and deliberately neither of the two obvious
  /// alternatives:
  ///
  ///  * **Not LiveKit's `setMuted`.** Muting is signalled to the server and
  ///    drawn as a muted microphone by every other client, so gating through it
  ///    would make everyone's participant list flicker in time with the
  ///    speaker's breathing. Disabling the media track sends silence and says
  ///    nothing.
  ///  * **Not `Helper.setVolume(0)`.** That lands on
  ///    `AudioSourceInterface::SetVolume`, which libwebrtc implements for
  ///    *remote* sources — it is playout gain — and leaves as an empty base
  ///    method for a local capture source. The call would be accepted and do
  ///    nothing, which for a gate is the worst available failure: silently not
  ///    gating. And if it did work it would still be the wrong lever, because
  ///    automatic gain control is on by default and spends the next second or
  ///    two pulling the level back up.
  ///
  /// A hard cut rather than a ramp is fine here, and that is the hold's doing:
  /// the gate closes 400ms *after* the level drops, so the transition happens
  /// during silence rather than across a waveform. There is nothing to click.
  Future<void> _setMicrophoneOpen(bool open) async {
    final track = _localTrack();
    if (track == null) return;

    final sender = track.sender;
    final senderId = sender?.senderId;

    // A new sender starts active and knows nothing about the gate, so the
    // shortcut below is only valid while we are talking about the same one.
    if (senderId != _muzzledSenderId) {
      _muzzled = false;
      _muzzledSenderId = senderId;
      _gateEffective = true;
    }

    if (open == !_muzzled) return;
    _muzzled = !open;

    try {
      if (sender != null) {
        // Deactivate the RTP encoding, leaving the track attached.
        //
        // This is the third mechanism tried, and the first that can work. The
        // other two both stopped the measurement along with the audio:
        //
        //  * `mediaStreamTrack.enabled = false` stops a track feeding its
        //    sinks, and the tap is one of them.
        //  * `sender.replaceTrack(null)` detaches the track — and WebRTC only
        //    runs the capture pipeline while a sender is consuming it, so the
        //    microphone stops being read at all. Observed: the gate closed,
        //    went blind, and had to be rescued by the fail-safe every time.
        //
        // Setting `active: false` on the encoding leaves the track attached
        // and the capture running — the encoder still pulls audio, the tap
        // still sees it — while nothing is put on the wire. Which is the whole
        // requirement: stop sending without stopping listening.
        final parameters = sender.parameters;
        // See `gate_encodings.dart`: an audio sender frequently reports no
        // encodings at all, and handing that straight back is a request that
        // sets nothing and still reports success.
        parameters.encodings = gateEncodings(parameters, open: open);
        final applied = await sender.setParameters(parameters);

        // The one result that used to be thrown away. A refusal here is the
        // gate being ignored, and the difference between that and a working
        // gate is inaudible from this end — which is exactly why it has to be
        // said out loud rather than inferred.
        if (!applied) {
          if (_gateEffective) {
            debugPrint(
              '[voice] the sender refused to ${open ? 'reopen' : 'close'} the '
              'gate; audio is still being sent. The breakpoint cannot work on '
              'this build.',
            );
          }
          _gateEffective = false;
        } else {
          _gateEffective = true;
        }
      } else {
        // No sender yet — publishing has not finished. Nothing is being sent
        // anyway, so there is nothing to gate.
        track.mediaStreamTrack.enabled = open;
      }
    } catch (error) {
      // Never stay shut on a failure: an unsent word is recoverable, a
      // microphone stuck closed by an error nobody saw is not.
      debugPrint(
        '[voice] could not ${open ? 'open' : 'close'} the gate: $error',
      );
      _muzzled = false;
      _gateEffective = false;
    }
  }

  Future<void> _openMicrophone() => _setMicrophoneOpen(true);
}

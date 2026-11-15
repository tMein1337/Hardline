// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'mic_tap.dart';

/// How long the level must stay below the breakpoint before the gate closes.
///
/// **600ms, and it was 400.** 400 is the figure usually quoted for voice gates,
/// and it was measured too short here: a voice played into the microphone
/// with ordinary 250ms pauses between words, the breakpoint set just above
/// the room as the settings tell people to set it, reached the other end of
/// a call with a 200ms hole between two of the words
/// (`integration_test/call_flow.dart`).
///
/// The reason is the measurement, not the speaker. The level is read every
/// 100ms, as that interval's peak, and the end of a word is quieter than its
/// middle — so a soft last syllable reads below the line before the pause has
/// even begun. A soft syllable plus a short pause is already more than 400ms
/// "below", in the middle of somebody's sentence.
///
/// The cost is that noise follows the end of speech for 600ms rather than
/// 400ms before the gate shuts. That is a cough's tail audible a moment
/// longer, against words arriving with holes in them; the second is the
/// failure people actually complain about.
const kGateHold = Duration(milliseconds: 600);

/// Decides, from a stream of microphone levels in dB, whether to transmit.
///
/// Pure and synchronous: it takes a level and a timestamp and returns a
/// decision. Nothing in here knows about LiveKit, WebRTC or Riverpod, which is
/// what makes the awkward part — the hold — worth testing rather than worth
/// hoping about.
///
/// ## Why a gate needs more than a threshold
///
/// Comparing the level against a number and muting when it drops below would
/// cut the ends off words and swallow the pauses inside sentences. Speech is
/// not continuous; it is bursts with gaps of tens to hundreds of milliseconds.
/// So the gate opens the instant the level goes over, and closes only after
/// [hold] has passed *entirely* below.
///
/// ## There is no fail-safe, deliberately
///
/// There used to be one: a gate held shut for three seconds without the level
/// ever rising off `MicTap.silenceDb` concluded it had blinded itself — that
/// its own closing had stopped the measurement arriving — gave up, and stayed
/// open. It rested on the claim that a genuinely quiet room never reads the
/// absolute floor, because there is always a noise floor of some kind.
///
/// That claim is false on a great many real machines. `takePeakDb` returns
/// exactly `silenceDb` both when the tap delivered a zero band *and* when it
/// delivered nothing at all, so "silent" and "blind" are the same number
/// downstream — and digital silence is what a hardware-muted headset, a
/// virtual audio cable, and any of the vendor noise suppressors (Sonar,
/// Nvidia Broadcast, Krisp) emit while they decide you are not talking. Those
/// setups tripped the fail-safe within seconds of the gate first closing, and
/// the gate then stopped gating for the rest of the call while the settings
/// pane went on saying it was on.
///
/// **A false positive is worse than the failure it guarded against**, because
/// the guarded failure has an obvious symptom and a one-click fix: nobody can
/// hear you, and the switch is in Settings → Voice & Video. A fail-safe that
/// fires on ordinary silence has no symptom at all — the gate simply does
/// nothing, quietly, and the person who turned it on believes it is working.
///
/// So the gate now does exactly what it is told, and stopping it is the user's
/// job rather than a guess this code makes on their behalf. The meter is what
/// makes that possible: it says whether anything is being sent, which is the
/// fact somebody needs in order to reach for the switch.
class NoiseGate {
  NoiseGate({required this.thresholdDb, this.hold = kGateHold});

  /// Decibels at or above which the gate opens, on the same scale [MicTap]
  /// reports — so a threshold read off the meter is the threshold to set.
  final double thresholdDb;

  /// How long the level must stay below [thresholdDb] before the gate closes.
  ///
  /// See [kGateHold].
  final Duration hold;

  bool _open = false;
  DateTime? _lastAbove;

  /// Whether audio should currently be transmitted.
  bool get isOpen => _open;

  /// Feeds one measurement in decibels and returns whether the gate is open.
  ///
  /// [now] is passed rather than read so the state machine can be tested
  /// without waiting in real time.
  bool update(double db, DateTime now) {
    if (db >= thresholdDb) {
      _lastAbove = now;
      _open = true;
      return true;
    }

    if (!_open) return false;

    final since = _lastAbove;
    if (since != null && now.difference(since) < hold) return true;

    _open = false;
    return false;
  }

  /// Forgets everything, for a new call or a new microphone.
  void reset() {
    _open = false;
    _lastAbove = null;
  }
}

/// The microphone level, and what the gate did about it.
///
/// One value so a widget can draw the meter and the gate's state without
/// listening to two things that could disagree for a frame.
@immutable
class MicLevel {
  const MicLevel({
    required this.db,
    required this.speaking,
    required this.gateOpen,
    required this.gateActive,
    this.gateAvailable = true,
  }) : measured = true;

  /// Nothing measured: not in a call, or the microphone is muted.
  const MicLevel.none()
    : db = MicTap.silenceDb,
      speaking = false,
      gateOpen = false,
      gateActive = false,
      gateAvailable = true,
      measured = false;

  /// Decibels, on [MicTap]'s scale.
  final double db;

  /// Whether there is a microphone to read at all.
  ///
  /// Distinct from a reading of silence: the meter says "join a call" for one
  /// and draws an empty bar for the other, and those are different facts.
  final bool measured;

  /// Whether the level is over the breakpoint, with the same hold the gate
  /// uses.
  ///
  /// **Not the same question as [gateOpen]**, and conflating the two is how
  /// the ring got stuck on: with the gate switched off nothing is ever being
  /// withheld, so `gateOpen` is permanently true, and an avatar wired to it
  /// lights up on the first sample of a call and never goes out again.
  final bool speaking;

  /// Whether audio is being transmitted right now.
  ///
  /// True whenever the gate is off, because then nothing is being withheld.
  final bool gateOpen;

  /// Whether the gate is switched on and doing anything.
  ///
  /// False when the user has turned it off, and false when the sender refused
  /// the change — see `gateAvailable`. There is no third case: the gate does
  /// not give up on its own any more, deliberately. See the class comment.
  final bool gateActive;

  /// Whether gating is possible at all on this build.
  ///
  /// False when the level is coming from statistics rather than from the tap,
  /// which happens when the native visualizer never started. The reading is
  /// still good — good enough for the meter and for the speaking ring — but it
  /// is measured on the very track the gate would disable, so the gate is not
  /// offered rather than offered and quietly broken.
  final bool gateAvailable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MicLevel &&
          db == other.db &&
          speaking == other.speaking &&
          gateOpen == other.gateOpen &&
          gateActive == other.gateActive &&
          gateAvailable == other.gateAvailable &&
          measured == other.measured;

  @override
  int get hashCode =>
      Object.hash(db, speaking, gateOpen, gateActive, gateAvailable, measured);
}

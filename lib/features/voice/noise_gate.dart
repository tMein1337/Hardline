// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'mic_tap.dart';

/// Decides, from a stream of microphone levels in dB, whether to transmit.
///
/// Pure and synchronous: it takes a level and a timestamp and returns a
/// decision. Nothing in here knows about LiveKit, WebRTC or Riverpod, which is
/// what makes the awkward parts — the hold, the release, the fail-safe — worth
/// testing rather than worth hoping about.
///
/// ## Why a gate needs more than a threshold
///
/// Comparing the level against a number and muting when it drops below would
/// cut the ends off words and swallow the pauses inside sentences. Speech is
/// not continuous; it is bursts with gaps of tens to hundreds of milliseconds.
/// So the gate opens the instant the level goes over, and closes only after
/// [hold] has passed *entirely* below.
///
/// ## The fail-safe, and why it exists
///
/// The gate closes by disabling the capture track. If whatever is measuring
/// that microphone sits *downstream* of the gate, a closed gate reads silence,
/// concludes the room is quiet, and never reopens — leaving somebody inaudible
/// with a microphone that looks perfectly live, until they restart the app.
///
/// `MicTap` is built so that cannot happen: it reads the capture source, above
/// the gate, so the two paths never touch. This is the belt to that pair of
/// braces. A gate closed for [failSafe] without the level ever rising off
/// `MicTap.silenceDb` concludes it has been blinded anyway, gives up, and stays
/// open — because the failure it is guarding against is silent, and for a
/// microphone "no gate" is the only acceptable direction to fail in.
///
/// A genuinely quiet room never reads the absolute floor; there is always a
/// noise floor of some kind. Only a reading pinned at the very bottom of the
/// scale says the measurement has stopped arriving.
class NoiseGate {
  NoiseGate({
    required this.thresholdDb,
    this.hold = const Duration(milliseconds: 400),
    this.failSafe = const Duration(seconds: 3),
  });

  /// Decibels at or above which the gate opens, on the same scale [MicTap]
  /// reports — so a threshold read off the meter is the threshold to set.
  final double thresholdDb;

  /// How long the level must stay below [thresholdDb] before the gate closes.
  ///
  /// Long enough to carry the pause between words, short enough that a room
  /// going quiet does not keep transmitting for noticeably long. 400ms is the
  /// usual figure for voice gates and is what Discord's own release lands near.
  final Duration hold;

  /// How long a closed gate tolerates a level pinned at the floor before it
  /// concludes it has blinded itself and reopens. See the class comment.
  ///
  /// **Null disables it**, which is right for an instance that gates nothing.
  /// The whole hazard is a gate silencing the thing it measures; one driving
  /// only an indicator silences nothing, has nothing to be blinded by, and
  /// would be wrong to give up — a permanently-lit ring is its own bug.
  final Duration? failSafe;

  bool _open = false;
  bool _defeated = false;
  DateTime? _lastAbove;
  DateTime? _closedAt;

  /// Whether audio should currently be transmitted.
  bool get isOpen => _open || _defeated;

  /// True once the fail-safe has fired and the gate has stopped gating.
  ///
  /// Surfaced rather than hidden: a gate that has given up is a thing the
  /// settings pane should be able to say out loud, because the alternative is
  /// a slider that silently does nothing.
  bool get isDefeated => _defeated;

  /// Feeds one measurement in decibels and returns whether the gate is open.
  ///
  /// [now] is passed rather than read so the state machine can be tested
  /// without waiting in real time.
  bool update(double db, DateTime now) {
    if (_defeated) return true;

    if (db >= thresholdDb) {
      _lastAbove = now;
      _open = true;
      _closedAt = null;
      return true;
    }

    if (!_open) {
      // Already shut. If nothing but the absolute floor has been seen for long
      // enough, the measurement has stopped arriving rather than gone quiet.
      if (db > MicTap.silenceDb) {
        _closedAt = now;
      } else if (failSafe != null &&
          _closedAt != null &&
          now.difference(_closedAt!) >= failSafe!) {
        _defeated = true;
        _open = true;
      }
      return isOpen;
    }

    final since = _lastAbove;
    if (since != null && now.difference(since) < hold) return true;

    _open = false;
    _closedAt = now;
    return false;
  }

  /// Forgets everything, for a new call or a new microphone.
  ///
  /// The fail-safe verdict is forgotten too: it was a conclusion about one
  /// track on one device, and the next one deserves to be judged fresh.
  void reset() {
    _open = false;
    _defeated = false;
    _lastAbove = null;
    _closedAt = null;
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

  /// Whether the gate is switched on and doing anything. False when the user
  /// has turned it off, and false once the fail-safe has defeated it.
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

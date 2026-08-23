// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'livekit_call_controller.dart' show matrixUserIdOf;

/// Who is audible right now, and in whose call.
///
/// A value rather than a live view of LiveKit's participants, for the reason
/// `VoiceParticipant` gives: LiveKit mutates its participant objects in place,
/// so holding one would make equality meaningless — and equality is the whole
/// point here. This is compared several times a second, and an avatar that
/// repaints when *somebody else* starts talking is a repaint for nothing.
///
/// Keyed by Matrix user id, not by LiveKit identity. One person can be in a
/// call from two devices, and the avatar drawn for them is one avatar; whether
/// the laptop or the desk microphone carried the audio is not something a ring
/// around a face can express.
@immutable
class SpeakingParticipants {
  const SpeakingParticipants({required this.roomId, required this.userIds});

  /// Nobody, anywhere — the state before a call and after one.
  const SpeakingParticipants.silent() : roomId = null, userIds = const {};

  /// Reduces LiveKit participant identities to the people behind them.
  factory SpeakingParticipants.fromIdentities(
    String? roomId,
    Iterable<String> identities,
  ) => SpeakingParticipants(
    roomId: roomId,
    userIds: {for (final identity in identities) matrixUserIdOf(identity)},
  );

  /// The Matrix room whose call this describes, or null when there is no call.
  ///
  /// Carried so a ring cannot leak between rooms. Somebody in two calls at once
  /// — one from a laptop, one from a phone — is listed under both channels in
  /// the sidebar, and only the channel we are actually connected to can know
  /// whether they are talking.
  final String? roomId;

  final Set<String> userIds;

  /// Whether [userId] is speaking in a call we can hear.
  ///
  /// [inRoom] of null means "whichever call this client is in", which is what
  /// the user footer wants: it is not tied to a room, and the only question it
  /// asks is whether the microphone is picking *you* up.
  bool contains(String userId, {String? inRoom}) =>
      roomId != null &&
      (inRoom == null || inRoom == roomId) &&
      userIds.contains(userId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeakingParticipants &&
          roomId == other.roomId &&
          setEquals(userIds, other.userIds);

  @override
  int get hashCode => Object.hash(roomId, Object.hashAllUnordered(userIds));

  @override
  String toString() => 'SpeakingParticipants($roomId, $userIds)';
}

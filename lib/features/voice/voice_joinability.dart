// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'matrix_rtc_membership.dart';

/// Whether the user can join a room's call, and what it would cost.
enum VoiceJoinability {
  /// Ready to go — the room already permits `com.famedly.call.member`.
  joinable,

  /// We may join, but only by first changing the room's power levels so that
  /// everyone can. See [VoiceJoinability] docs for why that needs consent.
  needsEnabling,

  /// Calls are not enabled here and we lack the power to enable them.
  forbidden,

  /// Not a member of the room, so there is nothing to join.
  notJoined,
}

/// Classifies a room for the join button, without side effects.
///
/// Joining means writing an `org.matrix.msc3401.call.member` state event, so the
/// question is simply whether we may send that state event. A fresh Synapse room
/// has `state_default: 50`, which means **only moderators can join a call** until
/// someone lowers it — so [needsEnabling] or [forbidden] is the *normal* first
/// answer for a room nobody has set up for calls, not an edge case.
///
/// Deliberately does not use `room.canJoinGroupCall`: that SDK getter checks
/// `com.famedly.call.member`, a different event type that no Element client uses.
/// A room could report `canJoinGroupCall == true` and still reject our state
/// event, or the reverse.
///
/// Note for room version 12 and above the creator has implicit maximum power
/// with no entry in the `users` map; `room.canChangeStateEvent` accounts for
/// that (`room.dart:2219`), so this does not need to.
VoiceJoinability joinabilityOf(Room room) {
  if (room.membership != Membership.join) return VoiceJoinability.notJoined;
  if (room.canChangeStateEvent(kCallMemberEventType)) {
    return VoiceJoinability.joinable;
  }
  if (room.canChangePowerLevel) return VoiceJoinability.needsEnabling;
  return VoiceJoinability.forbidden;
}

/// Lowers the power level required to join calls in [room] to the room default.
///
/// This is a **permanent, room-wide permission change visible to every member**,
/// and this app offers no way to undo it — so it must never run as a silent side
/// effect of clicking Join. The caller is responsible for asking first.
Future<void> enableCallsForEveryone(Room room) async {
  final powerLevels = Map<String, Object?>.from(
    room.getState(EventTypes.RoomPowerLevels)?.content ?? const {},
  );

  final events = Map<String, Object?>.from(
    (powerLevels['events'] as Map?)?.cast<String, Object?>() ?? const {},
  );
  events[kCallMemberEventType] = powerLevels['users_default'] ?? 0;
  powerLevels['events'] = events;

  await room.client.setRoomStateWithKey(
    room.id,
    EventTypes.RoomPowerLevels,
    '',
    powerLevels,
  );
}

import 'package:flutter/foundation.dart';

import '../voice/voice_joinability.dart';

/// One message by someone, somewhere, as a row draws it.
///
/// The names and avatar are resolved here rather than stored in the log — see
/// `MessageRecord` for why. Holds no `Event` reference either: the SDK mutates
/// events in place, so keeping one would make equality meaningless and defeat
/// the snapshot mechanism in `snapshot_list.dart`.
@immutable
class MessageActivity {
  const MessageActivity({
    required this.eventId,
    required this.roomId,
    required this.roomName,
    required this.userId,
    required this.displayName,
    required this.avatarMxc,
    required this.preview,
    required this.timestamp,
  });

  final String eventId;
  final String roomId;
  final String roomName;
  final String userId;
  final String displayName;
  final String? avatarMxc;

  /// One line of plain text. Already collapsed and truncated on capture, so
  /// nothing downstream has to guard against a novel arriving in a list row.
  final String preview;

  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageActivity &&
          eventId == other.eventId &&
          roomId == other.roomId &&
          roomName == other.roomName &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarMxc == other.avatarMxc &&
          preview == other.preview &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(
    eventId,
    roomId,
    roomName,
    userId,
    displayName,
    avatarMxc,
    preview,
    timestamp,
  );
}

/// A followed person sitting in a room's call.
///
/// One entry per (person, room): somebody connected from two devices is one
/// person in one channel, and two identical rows would read as a bug — the same
/// rule `voiceParticipantsProvider` applies inside a single room.
@immutable
class VoiceActivity {
  const VoiceActivity({
    required this.userId,
    required this.displayName,
    required this.avatarMxc,
    required this.roomId,
    required this.roomName,
    required this.joinability,
  });

  final String userId;
  final String displayName;
  final String? avatarMxc;
  final String roomId;
  final String roomName;

  /// Carried rather than derived by the row, so a tile does not have to watch
  /// the sync tick to answer "can I join this?" — see `RoomListItem`.
  ///
  /// Whether *we* are already in that call is deliberately **not** here: it
  /// lives in `LiveKitCallController`, which is a `ChangeNotifier` and not
  /// provider state, so a snapshot of it would be stale the moment the call
  /// changed. The row reads it through a `ListenableBuilder`, exactly as
  /// `_JoinCallIcon` in the room list does.
  final VoiceJoinability joinability;

  bool get canJoin =>
      joinability == VoiceJoinability.joinable ||
      joinability == VoiceJoinability.needsEnabling;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceActivity &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarMxc == other.avatarMxc &&
          roomId == other.roomId &&
          roomName == other.roomName &&
          joinability == other.joinability;

  @override
  int get hashCode =>
      Object.hash(userId, displayName, avatarMxc, roomId, roomName, joinability);
}

/// A followed person who is typing, or who typed recently.
///
/// One row per person even when they are active in several rooms: the question
/// this list answers is "where is Alice", and three rows for one Alice answers
/// it worse than one.
@immutable
class UserActivity {
  const UserActivity({
    required this.userId,
    required this.displayName,
    required this.avatarMxc,
    required this.roomId,
    required this.roomName,
    required this.isTyping,
    required this.lastSpokeAt,
    required this.lastEventId,
  });

  final String userId;
  final String displayName;
  final String? avatarMxc;

  /// Where they are typing if they are, otherwise where they last spoke.
  final String roomId;
  final String roomName;

  final bool isTyping;

  /// Null when they are typing but have said nothing inside the window — that
  /// is a real state, and "typing…" with no timestamp is the honest rendering.
  final DateTime? lastSpokeAt;

  /// The message the row jumps to. Null while they are only typing.
  final String? lastEventId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserActivity &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarMxc == other.avatarMxc &&
          roomId == other.roomId &&
          roomName == other.roomName &&
          isTyping == other.isTyping &&
          lastSpokeAt == other.lastSpokeAt &&
          lastEventId == other.lastEventId;

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    avatarMxc,
    roomId,
    roomName,
    isTyping,
    lastSpokeAt,
    lastEventId,
  );
}

/// Somebody who can be followed, for the add-person picker.
@immutable
class FollowCandidate {
  const FollowCandidate({
    required this.userId,
    required this.displayName,
    required this.avatarMxc,
  });

  final String userId;
  final String displayName;
  final String? avatarMxc;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowCandidate &&
          userId == other.userId &&
          displayName == other.displayName &&
          avatarMxc == other.avatarMxc;

  @override
  int get hashCode => Object.hash(userId, displayName, avatarMxc);
}

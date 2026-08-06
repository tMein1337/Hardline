import 'package:flutter/foundation.dart';

/// One person shown in a channel's voice participant list.
///
/// Like `RoomListItem`, this holds no SDK object — no `CallMembership`, no
/// `Room`, no `User`. Those are mutated in place by the SDK, so keeping one
/// would make equality meaningless and defeat the `ListSnapshot` mechanism that
/// stops the sidebar repainting on every sync.
///
/// Only fields something actually draws belong here. Notably absent is
/// `isMuted`: whether someone has muted their own microphone never reaches
/// room state, so a person who has not joined the call cannot know it, and no
/// amount of work on our side changes that.
@immutable
class VoiceParticipant {
  const VoiceParticipant({
    required this.userId,
    required this.deviceIds,
    required this.displayName,
    required this.avatarMxc,
    required this.isScreensharing,
    required this.isSelf,
  });

  final String userId;

  /// Every device this person is connected from, sorted.
  ///
  /// The row collapses to one per person, but volume is stored per device — a
  /// laptop microphone and a desk microphone need different gains — so the
  /// per-user menu needs to know which devices to offer a slider for. Usually
  /// exactly one.
  final List<String> deviceIds;

  final String displayName;

  /// Raw `mxc://` string; resolving it to HTTP happens in the avatar widget.
  final String? avatarMxc;

  /// True when any of this person's connected devices is sharing a screen.
  ///
  /// Unlike mute, this *is* visible without joining: the screenshare feed's
  /// purpose is part of the `com.famedly.call.member` state event.
  final bool isScreensharing;

  final bool isSelf;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceParticipant &&
          userId == other.userId &&
          listEquals(deviceIds, other.deviceIds) &&
          displayName == other.displayName &&
          avatarMxc == other.avatarMxc &&
          isScreensharing == other.isScreensharing &&
          isSelf == other.isSelf;

  @override
  int get hashCode => Object.hash(
    userId,
    Object.hashAll(deviceIds),
    displayName,
    avatarMxc,
    isScreensharing,
    isSelf,
  );
}

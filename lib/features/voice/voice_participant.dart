// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'live_participant.dart';

/// One person shown in a channel's voice participant list.
///
/// Like `RoomListItem`, this holds no SDK object — no `CallMembership`, no
/// `Room`, no `User`. Those are mutated in place by the SDK, so keeping one
/// would make equality meaningless and defeat the `ListSnapshot` mechanism that
/// stops the sidebar repainting on every sync.
///
/// Only fields something actually draws belong here. Notably absent are
/// `isMuted` and `isScreensharing`. Neither reaches room state under MatrixRTC
/// — mute is never published at all, and a screen share is a LiveKit track
/// publication — so a person who has not joined the call cannot know either,
/// and no amount of work on our side changes that. Both are drawn from
/// `LiveKitCallController` instead, and only for the call we are in; see
/// `LiveParticipant`.
@immutable
class VoiceParticipant {
  const VoiceParticipant({
    required this.userId,
    required this.deviceIds,
    required this.displayName,
    required this.avatarMxc,
    required this.isSelf,
    this.deafened = false,
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

  final bool isSelf;

  /// Whether any of their devices says it has playback silenced.
  ///
  /// The one thing about somebody's audio that room state *can* carry, because
  /// this client puts it there — see `kDeafenedKey`. Mute still cannot be
  /// shown here; it never reaches room state at all.
  final bool deafened;

  /// The same person, described from a call we are connected to.
  ///
  /// The two models meet here and nowhere else. [VoiceParticipant] is built
  /// from Matrix room state and is one row per *person*; `LiveParticipant` is
  /// built from LiveKit and is one tile per *device*. The per-user audio menu
  /// is written against this one, so this is what lets a call tile open the
  /// same menu the sidebar row does rather than growing a second copy of it.
  ///
  /// [deviceIds] is every device that person is connected from — pass all of
  /// them, not just the tile's own, or right-clicking one of somebody's two
  /// tiles would offer a slider for half of them.
  factory VoiceParticipant.fromLive(
    LiveParticipant live, {
    required List<String> deviceIds,
  }) => VoiceParticipant(
    userId: live.userId,
    deviceIds: deviceIds,
    displayName: live.displayName,
    avatarMxc: live.avatarMxc,
    isSelf: live.isLocal,
    deafened: live.deafened,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceParticipant &&
          deafened == other.deafened &&
          userId == other.userId &&
          listEquals(deviceIds, other.deviceIds) &&
          displayName == other.displayName &&
          avatarMxc == other.avatarMxc &&
          isSelf == other.isSelf;

  @override
  int get hashCode => Object.hash(
    userId,
    Object.hashAll(deviceIds),
    displayName,
    avatarMxc,
    isSelf,
    deafened,
  );
}

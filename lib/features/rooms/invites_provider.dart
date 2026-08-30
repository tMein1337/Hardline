// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/room_buckets.dart';
import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/display_name.dart';
import '../../core/util/snapshot_list.dart';

/// An invitation waiting to be answered.
///
/// Holds no `Room`, for the reason `RoomListItem` does not: the SDK mutates
/// its objects in place, so keeping one would make equality meaningless and
/// defeat the snapshot comparison that stops the sidebar repainting on every
/// sync.
@immutable
class RoomInvite {
  const RoomInvite({
    required this.roomId,
    required this.name,
    required this.avatarMxc,
    required this.isSpace,
    required this.isEncrypted,
    required this.invitedBy,
    required this.inviterName,
  });

  final String roomId;
  final String name;
  final String? avatarMxc;
  final bool isSpace;
  final bool isEncrypted;

  /// Who sent it, or null when the invite event does not say.
  ///
  /// Worth showing rather than assuming: an invitation to a room you have
  /// never heard of is a very different thing depending on who sent it, and it
  /// is the only part of the decision this client can help with.
  final String? invitedBy;

  final String? inviterName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomInvite &&
          roomId == other.roomId &&
          name == other.name &&
          avatarMxc == other.avatarMxc &&
          isSpace == other.isSpace &&
          isEncrypted == other.isEncrypted &&
          invitedBy == other.invitedBy &&
          inviterName == other.inviterName;

  @override
  int get hashCode => Object.hash(
    roomId,
    name,
    avatarMxc,
    isSpace,
    isEncrypted,
    invitedBy,
    inviterName,
  );
}

RoomInvite _describe(Room room, Client client) {
  // The invite event names its sender, which is who invited us. Read from the
  // member event for our own id rather than from the room's heroes: an
  // invitation to a room with several members would otherwise credit whoever
  // happened to be listed first.
  final ownId = client.userID;
  final membership = ownId == null
      ? null
      : room.getState(EventTypes.RoomMember, ownId);
  final inviter = membership?.senderId;

  return RoomInvite(
    roomId: room.id,
    name: displaySafeName(room.getLocalizedDisplayname()),
    avatarMxc: room.avatar?.toString(),
    isSpace: room.isSpace,
    isEncrypted: room.encrypted,
    invitedBy: inviter,
    inviterName: inviter == null
        ? null
        : displaySafeName(
            room.unsafeGetUserFromMemoryOrFallback(inviter).calcDisplayname(),
            fallback: inviter,
          ),
  );
}

/// Invitations to ordinary rooms.
final roomInvitesProvider = Provider<ListSnapshot<RoomInvite>>((ref) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);
  return ListSnapshot([
    for (final room in invitedRooms(client)) _describe(room, client),
  ]);
});

/// Invitations to spaces.
final spaceInvitesProvider = Provider<ListSnapshot<RoomInvite>>((ref) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);
  return ListSnapshot([
    for (final room in invitedSpaces(client)) _describe(room, client),
  ]);
});

/// Accepts or declines an invitation.
///
/// Both are ordinary membership changes and both can fail — a room whose
/// invite has been withdrawn, or a server that will not have us — so the
/// caller gets the error rather than a silent no-op.
class InviteActions {
  const InviteActions(this._client);

  final Client _client;

  Future<void> accept(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw StateError('That invitation is no longer there.');
    await room.join();
  }

  /// Declining is `leave`, which is what Matrix calls refusing an invitation.
  ///
  /// Deliberately not followed by `forget`: forgetting drops the room from the
  /// account entirely, and somebody who declines by accident should be able to
  /// be invited again rather than having the record erased.
  Future<void> decline(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    await room.leave();
  }
}

final inviteActionsProvider = Provider<InviteActions>(
  (ref) => InviteActions(ref.watch(clientProvider)),
);

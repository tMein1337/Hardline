// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/util/display_name.dart';

/// One room a space says it contains.
@immutable
class SpaceChild {
  const SpaceChild({
    required this.roomId,
    required this.name,
    required this.topic,
    required this.memberCount,
    required this.avatarMxc,
    required this.isSpace,
    required this.isEncrypted,
    required this.joined,
  });

  final String roomId;
  final String name;
  final String? topic;
  final int memberCount;
  final String? avatarMxc;

  /// A space nested inside this one. Listed but not joinable from here.
  final bool isSpace;

  final bool isEncrypted;

  /// Whether this account is already in it.
  final bool joined;
}

/// What a space contains, from the server rather than from local state.
///
/// **Why not `Room.spaceChildren`**, which the room list already uses: that is
/// this client's view of the `m.space.child` events it happens to have synced,
/// and `roomsOfSpace` then drops every child not already joined. Which is
/// exactly the set somebody opening a space wants to see. The hierarchy
/// endpoint answers the other question — what is in here — including rooms
/// this account has never been in, with a name, a topic and a member count
/// that local state cannot supply for a room it has never seen.
///
/// A `FutureProvider` rather than something driven by `matrixTickProvider`:
/// this is a network call, and re-running it on every sync would be a request
/// per sync burst for a list that changes about once a month. It is refreshed
/// by hand after a join instead.
final spaceHierarchyProvider = FutureProvider.family<List<SpaceChild>, String>((
  ref,
  spaceId,
) async {
  final client = ref.watch(clientProvider);

  final response = await client.getSpaceHierarchy(spaceId, limit: 100);

  return [
    for (final room in response.rooms)
      // The space itself comes back in its own hierarchy, and listing it
      // inside itself would offer to join the thing you are looking at.
      if (room.roomId != spaceId)
        SpaceChild(
          roomId: room.roomId,
          name: displaySafeName(
            room.name ?? room.canonicalAlias ?? room.roomId,
          ),
          topic: room.topic == null ? null : displaySafeName(room.topic!),
          memberCount: room.numJoinedMembers,
          avatarMxc: room.avatarUrl?.toString(),
          isSpace: room.roomType == 'm.space',
          isEncrypted: room.encryption != null,
          joined:
              client.getRoomById(room.roomId)?.membership == Membership.join,
        ),
  ];
});

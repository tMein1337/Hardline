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

  /// A space nested inside this one. It has an overview of its own, which is
  /// where its rooms are listed.
  final bool isSpace;

  final bool isEncrypted;

  /// Whether this account is already in it.
  final bool joined;
}

/// What a space contains, as far as the server would say.
@immutable
class SpaceContents {
  const SpaceContents({required this.children, required this.truncated});

  final List<SpaceChild> children;

  /// Whether there is more that was not fetched.
  ///
  /// See [kMaxHierarchyRooms]. Carried so the overview can say so: a list
  /// that stops without a word reads as the whole list.
  final bool truncated;
}

/// How many rooms to ask for at a time.
const kHierarchyPageSize = 100;

/// Where reading a space stops.
///
/// The hierarchy is paged and this follows the pages, which it used not to do
/// — one request, a hundred rooms, and `next_batch` ignored, so a larger space
/// showed its first hundred and no sign there were more.
///
/// It does not follow them without limit. Each page is a request, a space is
/// opened by clicking on it, and there are spaces on the public federation
/// with thousands of rooms. A thousand is far more than anybody scrolls
/// through an overview to find, and few enough requests to finish.
const kMaxHierarchyRooms = 1000;

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
/// **One level, not the whole tree.** Without `max_depth` the endpoint walks
/// into every space beneath this one and returns the lot as a single flat
/// list, so a space holding three sub-spaces drew their rooms as its own, with
/// nothing to say which belonged where. A sub-space is listed here as one
/// entry; its rooms are on its own overview, where the rail now puts it.
///
/// A `FutureProvider` rather than something driven by `matrixTickProvider`:
/// this is a network call, and re-running it on every sync would be a request
/// per sync burst for a list that changes about once a month. It is refreshed
/// by hand after a join instead.
final spaceHierarchyProvider = FutureProvider.family<SpaceContents, String>((
  ref,
  spaceId,
) async {
  final client = ref.watch(clientProvider);

  final rooms = <SpaceRoomsChunk$2>[];
  String? from;
  var truncated = false;

  while (true) {
    final page = await client.getSpaceHierarchy(
      spaceId,
      limit: kHierarchyPageSize,
      maxDepth: 1,
      from: from,
    );
    rooms.addAll(page.rooms);

    from = page.nextBatch;
    if (from == null) break;
    // A server that hands back a token with an empty page would otherwise be
    // asked for the next one for ever.
    if (page.rooms.isEmpty || rooms.length >= kMaxHierarchyRooms) {
      truncated = true;
      break;
    }
  }

  return SpaceContents(
    truncated: truncated,
    children: [
      for (final room in rooms)
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
    ],
  );
});

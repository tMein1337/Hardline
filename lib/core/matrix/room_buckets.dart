// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'space_children.dart';

/// Joined, non-space rooms keyed by id.
Map<String, Room> joinedRoomsById(Client client) => {
  for (final room in client.rooms)
    if (!room.isSpace && room.membership == Membership.join) room.id: room,
};

/// Joined spaces, in the SDK's own ordering.
List<Room> joinedSpaces(Client client) => [
  for (final room in client.rooms)
    if (room.isSpace && room.membership == Membership.join) room,
];

/// Rooms this account has been invited to but has not answered.
///
/// **Nothing looked at these before.** Every bucket above filters on
/// `Membership.join`, so an invitation existed in the SDK and was invisible in
/// the app — there was no way to accept one, and no way to know one had
/// arrived. Somebody inviting you to a room might as well have not.
///
/// Split by kind because they belong in different places: a space invitation
/// is answered on the rail, where the space would appear, and a room
/// invitation at the top of the list it would join.
List<Room> invitedRooms(Client client) => [
  for (final room in client.rooms)
    if (!room.isSpace && room.membership == Membership.invite) room,
];

List<Room> invitedSpaces(Client client) => [
  for (final room in client.rooms)
    if (room.isSpace && room.membership == Membership.invite) room,
];

/// Rooms belonging to no space. These are what the home column lists.
List<Room> homeRooms(Client client) {
  final claimed = allSpaceChildIds(client);
  return [
    for (final room in joinedRoomsById(client).values)
      if (!claimed.contains(room.id)) room,
  ];
}

/// Joined rooms inside [spaceId], in the order the space defines.
///
/// Children that exist in the space but which we have not joined are skipped,
/// so the list only contains rooms that can actually be opened.
List<Room> roomsOfSpace(Client client, String spaceId) {
  final space = client.getRoomById(spaceId);
  if (space == null) return const [];

  final joined = joinedRoomsById(client);
  return [
    // Null-aware element: silently drops children we have not joined.
    for (final id in childRoomIdsOf(space)) ?joined[id],
  ];
}

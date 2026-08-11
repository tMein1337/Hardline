import 'package:matrix/matrix.dart';

/// The room ids a space lists as its children, in the space's own order.
///
/// Two SDK sharp edges are handled here so callers never meet them:
///
///  * `Room.spaceChildren` **throws** `Exception('Room is not a space!')` when
///    called on an ordinary room, so `isSpace` is checked first.
///  * `SpaceChild` is not exported from `package:matrix/matrix.dart`. Its type
///    can therefore never be written down without an implementation import, so
///    the loop below relies on inference and maps to `String` immediately.
///
/// Note the SDK filters out children with no `via` server list. A room added to
/// a space by a client that omitted `via` will not appear here — it falls into
/// the Home bucket instead. That is the usual explanation for a "missing"
/// channel.
List<String> childRoomIdsOf(Room room) {
  if (!room.isSpace) return const [];

  return [
    for (final child in room.spaceChildren)
      if (child.roomId != null) child.roomId!,
  ];
}

/// Every room id claimed by any joined space.
///
/// Used to compute the Home bucket: rooms belonging to no space at all.
Set<String> allSpaceChildIds(Client client) => {
  for (final room in client.rooms)
    if (room.isSpace) ...childRoomIdsOf(room),
};

/// The space claiming [roomId], or null when none does.
///
/// The inverse of how [allSpaceChildIds] builds the Home bucket, and the answer
/// anything that wants to *select* a room needs: the room list is keyed by
/// space, so opening a room means opening its space first, or the tile is not
/// in the column at all.
///
/// A room claimed by several spaces resolves to the first, matching the rail's
/// own ordering. Null covers a direct chat, and a room added to a space without
/// a `via` list — both of which the room list files under Home. Callers
/// substitute `kHomeSpaceId`; naming it here would make this core file depend
/// on the space feature that defines it.
String? spaceIdOfRoom(Client client, String roomId) {
  for (final room in client.rooms) {
    if (!room.isSpace) continue;
    if (childRoomIdsOf(room).contains(roomId)) return room.id;
  }
  return null;
}

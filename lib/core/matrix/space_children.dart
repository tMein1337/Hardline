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

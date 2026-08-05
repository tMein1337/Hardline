import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Everything the room list renders, and nothing else.
///
/// Named `RoomListItem` rather than `RoomSummary` because the Matrix SDK
/// exports its own `RoomSummary` (the `m.room.summary` wire type) and the two
/// would collide in every file that imports both.
///
/// Critically this holds no `Room` reference. `Room` is mutated in place by the
/// SDK, so keeping one here would make equality meaningless and defeat the
/// snapshot mechanism described in `snapshot_list.dart` — the app would still
/// work, but would repaint every column on every sync. Only add a field here
/// when a widget actually draws it.
@immutable
class RoomListItem {
  const RoomListItem({
    required this.id,
    required this.name,
    required this.avatarMxc,
    required this.isDirect,
    required this.isEncrypted,
    required this.notificationCount,
    required this.highlightCount,
  });

  final String id;
  final String name;

  /// The raw `mxc://` string; resolving it to an HTTP URL is async and happens
  /// in the avatar widget.
  final String? avatarMxc;

  final bool isDirect;
  final bool isEncrypted;
  final int notificationCount;
  final int highlightCount;

  bool get hasUnread => notificationCount > 0;
  bool get hasMention => highlightCount > 0;

  factory RoomListItem.from(Room room) => RoomListItem(
    id: room.id,
    name: room.getLocalizedDisplayname(),
    avatarMxc: room.avatar?.toString(),
    isDirect: room.isDirectChat,
    isEncrypted: room.encrypted,
    notificationCount: room.notificationCount,
    highlightCount: room.highlightCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomListItem &&
          id == other.id &&
          name == other.name &&
          avatarMxc == other.avatarMxc &&
          isDirect == other.isDirect &&
          isEncrypted == other.isEncrypted &&
          notificationCount == other.notificationCount &&
          highlightCount == other.highlightCount;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    avatarMxc,
    isDirect,
    isEncrypted,
    notificationCount,
    highlightCount,
  );
}

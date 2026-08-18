// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/hero_loader.dart';
import '../../core/matrix/room_buckets.dart';
import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/snapshot_list.dart';
import '../spaces/space_summary.dart';
import 'room_list_item.dart';

/// The rooms shown in the channel column for a given space.
///
/// Keyed by space id, so switching spaces creates a separate family instance
/// and leaves the rail's own subscription untouched.
///
/// Recomputes on every tick, but the resulting [ListSnapshot] has value
/// equality — a sync that changed nothing visible produces an equal snapshot
/// and notifies nobody.
final roomListProvider = Provider.family<ListSnapshot<RoomListItem>, String>((
  ref,
  spaceId,
) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);

  final rooms = spaceId == kHomeSpaceId
      ? homeRooms(client)
      : roomsOfSpace(client, spaceId);

  // Direct chats have no name until their members are loaded. This is
  // fire-once-per-room; see HeroLoader for why that matters.
  ref.read(heroLoaderProvider).ensureLoaded(rooms);

  return ListSnapshot([for (final room in rooms) RoomListItem.from(room)]);
});

/// Header details for the open room.
///
/// Separate from the list so renaming a room does not rebuild every tile, and
/// so the chat header does not rebuild when some other room's unread changes.
final roomHeaderProvider = Provider.family<RoomHeader?, String>((ref, roomId) {
  ref.watch(matrixTickProvider);
  final room = ref.watch(clientProvider).getRoomById(roomId);
  return room == null ? null : RoomHeader.from(room);
});

@immutable
class RoomHeader {
  const RoomHeader({
    required this.id,
    required this.name,
    required this.topic,
    required this.isEncrypted,
    required this.isDirect,
  });

  final String id;
  final String name;
  final String topic;
  final bool isEncrypted;
  final bool isDirect;

  factory RoomHeader.from(Room room) => RoomHeader(
    id: room.id,
    name: room.getLocalizedDisplayname(),
    topic: room.topic,
    isEncrypted: room.encrypted,
    isDirect: room.isDirectChat,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomHeader &&
          id == other.id &&
          name == other.name &&
          topic == other.topic &&
          isEncrypted == other.isEncrypted &&
          isDirect == other.isDirect;

  @override
  int get hashCode => Object.hash(id, name, topic, isEncrypted, isDirect);
}

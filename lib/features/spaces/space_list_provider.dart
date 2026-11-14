// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/room_buckets.dart';
import '../../core/matrix/space_children.dart';
import '../../core/matrix/space_tree.dart';
import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/snapshot_list.dart';
import '../shell/selection_providers.dart';
import 'space_summary.dart';

/// Entries for the left icon rail: Home first, then joined spaces.
///
/// Spaces live in `client.rooms` alongside ordinary rooms; `isSpace` is what
/// separates them.
///
/// A space inside another is drawn beneath it and only while that branch is
/// the one selected — `space_tree.dart` decides which, and says why. That is
/// the reason this watches the selection: the list is no longer the same for
/// every place you could be standing in.
final spaceListProvider = Provider<ListSnapshot<SpaceSummary>>((ref) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);
  final selectedId = ref.watch(selectedSpaceIdProvider);

  final home = homeRooms(client);
  final spaces = {for (final space in joinedSpaces(client)) space.id: space};

  final branches = railBranches(
    spaces: spaces.keys.toList(),
    childrenOf: {
      for (final space in spaces.values) space.id: childRoomIdsOf(space),
    },
    selectedId: selectedId,
  );

  return ListSnapshot([
    SpaceSummary.home(
      notificationCount: _sum(home, (r) => r.notificationCount),
      highlightCount: _sum(home, (r) => r.highlightCount),
    ),
    for (final branch in branches)
      SpaceSummary.from(
        spaces[branch.id]!,
        depth: branch.depth,
        foldedCount: branch.folded.length,
        contents: _contentsOf(client, branch, spaces),
      ),
  ]);
});

/// Everything [branch]'s rail entry is answerable for, each room once.
///
/// A room can be listed by a space and by a sub-space of it, and would
/// otherwise be counted for each.
Iterable<Room> _contentsOf(
  Client client,
  SpaceBranch branch,
  Map<String, Room> spaces,
) {
  final contents = <String, Room>{};
  for (final spaceId in [branch.id, ...branch.folded]) {
    if (spaceId != branch.id) contents[spaceId] = spaces[spaceId]!;
    for (final room in roomsOfSpace(client, spaceId)) {
      contents[room.id] = room;
    }
  }
  return contents.values;
}

int _sum(Iterable<Room> rooms, int Function(Room) selector) =>
    rooms.fold(0, (total, room) => total + selector(room));

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/room_buckets.dart';
import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/snapshot_list.dart';
import 'space_summary.dart';

/// Entries for the left icon rail: Home first, then joined spaces.
///
/// Spaces live in `client.rooms` alongside ordinary rooms; `isSpace` is what
/// separates them.
final spaceListProvider = Provider<ListSnapshot<SpaceSummary>>((ref) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);

  final home = homeRooms(client);

  return ListSnapshot([
    SpaceSummary.home(
      notificationCount: _sum(home, (r) => r.notificationCount),
      highlightCount: _sum(home, (r) => r.highlightCount),
    ),
    for (final space in joinedSpaces(client)) SpaceSummary.from(space),
  ]);
});

int _sum(Iterable<Room> rooms, int Function(Room) selector) =>
    rooms.fold(0, (total, room) => total + selector(room));

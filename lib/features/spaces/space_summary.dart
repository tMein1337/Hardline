// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import '../../core/util/display_name.dart';

/// Identifier for the pseudo-space holding rooms that belong to no real space.
const kHomeSpaceId = '@home';

/// One entry in the left icon rail.
///
/// Value type with no `Room` reference, for the reasons in `room_summary.dart`.
@immutable
class SpaceSummary {
  const SpaceSummary({
    required this.id,
    required this.name,
    required this.avatarMxc,
    required this.notificationCount,
    required this.highlightCount,
    this.depth = 0,
    this.foldedCount = 0,
  });

  /// The Home bucket, always pinned to the top of the rail.
  const SpaceSummary.home({
    required this.notificationCount,
    required this.highlightCount,
  }) : id = kHomeSpaceId,
       name = 'Home',
       avatarMxc = null,
       depth = 0,
       foldedCount = 0;

  final String id;
  final String name;
  final String? avatarMxc;
  final int notificationCount;
  final int highlightCount;

  /// How far in this space sits: 0 at the top, 1 for a space inside another.
  ///
  /// See `space_tree.dart` for which of them are on the rail at any moment.
  final int depth;

  /// How many spaces are folded away beneath this one.
  ///
  /// Their unread counts are already in [notificationCount] and
  /// [highlightCount] — an entry standing in for a branch nobody can see has
  /// to carry that branch's badge, or a mention in there is one nobody reads.
  final int foldedCount;

  bool get isHome => id == kHomeSpaceId;
  bool get hasUnread => notificationCount > 0;
  bool get hasMention => highlightCount > 0;

  /// [contents] is everything this entry stands for besides the space room
  /// itself: the rooms in it, and — while they are folded away — the spaces
  /// beneath it and the rooms in those.
  ///
  /// The counts are the sum over all of it. They used to be the space room's
  /// own, and a space room holds no conversation: a space's rail entry could
  /// only ever light up for an invitation to the space itself, while Home,
  /// which sums its rooms, lit up for everything. Somebody could be mentioned
  /// in a space they were not looking at and see nothing change.
  factory SpaceSummary.from(
    Room space, {
    int depth = 0,
    int foldedCount = 0,
    Iterable<Room> contents = const [],
  }) => SpaceSummary(
    id: space.id,
    name: displaySafeName(space.getLocalizedDisplayname()),
    avatarMxc: space.avatar?.toString(),
    notificationCount: contents.fold(
      space.notificationCount,
      (total, room) => total + room.notificationCount,
    ),
    highlightCount: contents.fold(
      space.highlightCount,
      (total, room) => total + room.highlightCount,
    ),
    depth: depth,
    foldedCount: foldedCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpaceSummary &&
          id == other.id &&
          name == other.name &&
          avatarMxc == other.avatarMxc &&
          notificationCount == other.notificationCount &&
          highlightCount == other.highlightCount &&
          depth == other.depth &&
          foldedCount == other.foldedCount;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    avatarMxc,
    notificationCount,
    highlightCount,
    depth,
    foldedCount,
  );
}

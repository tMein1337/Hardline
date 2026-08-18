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
  });

  /// The Home bucket, always pinned to the top of the rail.
  const SpaceSummary.home({
    required this.notificationCount,
    required this.highlightCount,
  }) : id = kHomeSpaceId,
       name = 'Home',
       avatarMxc = null;

  final String id;
  final String name;
  final String? avatarMxc;
  final int notificationCount;
  final int highlightCount;

  bool get isHome => id == kHomeSpaceId;
  bool get hasUnread => notificationCount > 0;
  bool get hasMention => highlightCount > 0;

  factory SpaceSummary.from(Room space) => SpaceSummary(
    id: space.id,
    name: displaySafeName(space.getLocalizedDisplayname()),
    avatarMxc: space.avatar?.toString(),
    notificationCount: space.notificationCount,
    highlightCount: space.highlightCount,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpaceSummary &&
          id == other.id &&
          name == other.name &&
          avatarMxc == other.avatarMxc &&
          notificationCount == other.notificationCount &&
          highlightCount == other.highlightCount;

  @override
  int get hashCode =>
      Object.hash(id, name, avatarMxc, notificationCount, highlightCount);
}

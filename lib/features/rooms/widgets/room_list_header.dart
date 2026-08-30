// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/room_capabilities.dart';
import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import '../../spaces/space_summary.dart';
import '../../spaces/widgets/create_room_dialog.dart';
import 'room_list_title.dart';

/// Title bar of the channel column, showing the selected space's name.
///
/// The name is also the way back to the space itself. Opening a room fills the
/// chat column with it, and there was then nothing left that would show the
/// space overview again — the rail deliberately restores the room you had
/// open, so tapping the space you are already in changes nothing. Which left
/// the list of rooms in a space, and the join button on each of them,
/// reachable exactly once per session.
///
/// The two affordances say different things and both are worth having: the
/// rail is "go to this space, where I left it", the name is "show me this
/// space". On Home the same tap returns to the activity summary, which is the
/// same relationship in the same place.
class RoomListHeader extends ConsumerWidget {
  const RoomListHeader({super.key, required this.title, required this.spaceId});

  final String title;

  /// Which space the column is showing, so a new room lands in it.
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Container(
      height: context.metrics.headerHeight,
      padding: const EdgeInsets.only(left: 16, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.dividerStrong)),
      ),
      child: Row(
        children: [
          Expanded(
            child: RoomListTitle(title: title, spaceId: spaceId),
          ),
          if (_canCreateHere(ref))
            IconButton(
              tooltip: spaceId == kHomeSpaceId
                  ? 'Create a room'
                  : 'Create a room in this space',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              color: colors.textMuted,
              icon: const Icon(Icons.add),
              onPressed: () => CreateRoomDialog.show(
                context,
                kind: CreateKind.room,
                parentSpaceId: spaceId == kHomeSpaceId ? null : spaceId,
              ),
            ),
        ],
      ),
    );
  }

  /// Whether the control is worth offering.
  ///
  /// On Home, always: a room with no space is something any account can make,
  /// and the homeserver is the only thing that could refuse.
  ///
  /// Inside a space, only when this account could actually add the new room to
  /// it. Creating a room that then could not be filed anywhere would leave it
  /// stranded in the Home list, which is not what the button appeared to
  /// promise.
  bool _canCreateHere(WidgetRef ref) {
    if (spaceId == kHomeSpaceId) return true;
    final space = ref.watch(clientProvider).getRoomById(spaceId);
    return space != null && canAddToSpace(space);
  }
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../../common/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../shell/selection_providers.dart';
import '../../spaces/space_summary.dart';

/// The space's name, which doubles as the way back to it.
class RoomListTitle extends ConsumerWidget {
  const RoomListTitle({super.key, required this.title, required this.spaceId});

  final String title;
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isHome = spaceId == kHomeSpaceId;

    // Nothing to go back *to* when no room is open — the space view is
    // already what the column is next to. Left inert rather than hidden, so
    // the header does not change shape as rooms are opened and closed.
    final openRoom = ref.watch(selectedRoomIdsProvider)[spaceId];
    if (openRoom == null) {
      return Text(
        title,
        style: context.text.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return AppTooltip(
      message: isHome ? 'Back to recent activity' : 'Show what is in $title',
      child: Hoverable(
        onTap: () => ref.read(selectedRoomIdsProvider.notifier).clear(spaceId),
        builder: (context, hovered) => Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: context.text.title.copyWith(
              // The only tell that it is clickable, and only on hover: a
              // permanently accented header would read as a selected state
              // rather than as a control.
              color: hovered ? colors.accent : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

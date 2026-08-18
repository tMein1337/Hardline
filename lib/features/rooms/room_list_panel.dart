// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../shell/selection_providers.dart';
import '../spaces/space_list_provider.dart';
import '../spaces/space_summary.dart';
import '../voice/widgets/voice_channel_participants.dart';
import '../voice/widgets/voice_status_footer.dart';
import 'room_list_provider.dart';
import 'widgets/room_list_header.dart';
import 'widgets/room_list_tile.dart';
import 'widgets/user_footer.dart';

/// The middle column: rooms of the selected space, plus the user footer.
class RoomListPanel extends ConsumerWidget {
  const RoomListPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final spaceId = ref.watch(selectedSpaceIdProvider);
    final rooms = ref.watch(roomListProvider(spaceId));
    final selectedRoomId = ref.watch(selectedRoomIdProvider);

    final spaceName = ref
        .watch(spaceListProvider)
        .items
        .where((space) => space.id == spaceId)
        .map((space) => space.name)
        .firstOrNull;

    return Container(
      width: context.metrics.sidebarWidth,
      color: colors.roomSidebar,
      child: Column(
        children: [
          RoomListHeader(title: spaceName ?? 'Home'),
          Expanded(
            child: rooms.isEmpty
                ? _EmptyRoomList(isHome: spaceId == kHomeSpaceId)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: rooms.length,
                    itemBuilder: (context, index) {
                      final room = rooms[index];
                      // The participant list collapses to nothing when no call
                      // is running, so this Column is a plain tile in the
                      // overwhelmingly common case.
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RoomListTile(
                            room: room,
                            selected: room.id == selectedRoomId,
                            onTap: () => ref
                                .read(selectedRoomIdsProvider.notifier)
                                .select(spaceId: spaceId, roomId: room.id),
                          ),
                          VoiceChannelParticipants(roomId: room.id),
                        ],
                      );
                    },
                  ),
          ),
          const VoiceStatusFooter(),
          const UserFooter(),
        ],
      ),
    );
  }
}

class _EmptyRoomList extends StatelessWidget {
  const _EmptyRoomList({required this.isHome});

  final bool isHome;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          isHome
              ? 'No rooms yet.\nRooms that belong to no space appear here.'
              : 'This space has no rooms you have joined.',
          textAlign: TextAlign.center,
          style: context.text.subtitle,
        ),
      ),
    );
  }
}

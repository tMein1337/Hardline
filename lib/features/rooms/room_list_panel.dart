// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../shell/selection_providers.dart';
import '../spaces/space_list_provider.dart';
import '../spaces/space_summary.dart';
import '../voice/join_voice_action.dart';
import '../voice/voice_participants_provider.dart';
import '../voice/voice_prefs_controller.dart';
import '../voice/widgets/voice_channel_participants.dart';
import '../voice/widgets/voice_status_footer.dart';
import 'room_list_provider.dart';
import 'invites_provider.dart';
import 'widgets/invite_card.dart';
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
    final doubleClickToJoin = ref.watch(
      voicePrefsProvider.select((prefs) => prefs.doubleClickToJoin),
    );

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
          RoomListHeader(title: spaceName ?? 'Home', spaceId: spaceId),
          // Only on Home, and above everything else.
          //
          // An invitation has no space yet — accepting one is what decides
          // where the room lands — so there is no space column it could
          // sensibly belong to, and Home is the list that shows what belongs
          // nowhere. Above the rooms because it is the only thing here waiting
          // on an answer.
          if (spaceId == kHomeSpaceId)
            for (final invite in ref.watch(roomInvitesProvider).items)
              InviteCard(key: ValueKey(invite.roomId), invite: invite),
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
                            // Only when asked for, and only when there is a
                            // call to join: binding this on every row would
                            // put the double-tap delay on every room switch,
                            // and offering it on a channel with nobody in it
                            // would mean starting a call by mistiming a click.
                            onDoubleTap:
                                doubleClickToJoin &&
                                    ref
                                        .watch(
                                          voiceParticipantsProvider(room.id),
                                        )
                                        .isNotEmpty
                                ? () => joinVoiceCall(
                                    context,
                                    ref,
                                    room.id,
                                    room.voiceJoinability,
                                  )
                                : null,
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

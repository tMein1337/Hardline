import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../activity/activity_page.dart';
import '../rooms/room_list_provider.dart';
import '../shell/selection_providers.dart';
import '../spaces/space_summary.dart';
import '../voice/widgets/call_stage.dart';
import 'widgets/chat_drop_target.dart';
import 'widgets/chat_header.dart';
import 'widgets/empty_chat_view.dart';
import 'widgets/message_composer.dart';
import 'widgets/message_list.dart';

/// The right-hand column: header, messages, composer.
class ChatPanel extends ConsumerWidget {
  const ChatPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomId = ref.watch(selectedRoomIdProvider);
    if (roomId == null) return const _NoRoomView();

    final header = ref.watch(roomHeaderProvider(roomId));
    if (header == null) return const _NoRoomView();

    return Container(
      color: context.colors.chatBackground,
      child: Column(
        children: [
          ChatHeader(header: header),
          // Collapses to nothing unless this room's call is carrying video, so
          // a text-only room renders exactly as it did before voice existed.
          CallStage(roomId: roomId),
          Expanded(
            // Covers the message list and the composer, so a file can be
            // dropped anywhere in the chat area. Deliberately excludes the
            // header — dropping on a room title means nothing — and the
            // CallStage, whose native video views swallow hit tests.
            child: ChatDropTarget(
              roomId: roomId,
              roomName: header.name,
              child: Column(
                children: [
                  Expanded(
                    // Keyed by room so switching rooms rebuilds the list state
                    // (scroll position, controller) instead of reusing the old
                    // one.
                    child: MessageList(
                      key: ValueKey(roomId),
                      roomId: roomId,
                      roomName: header.name,
                    ),
                  ),
                  MessageComposer(roomId: roomId, roomName: header.name),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What fills the column when no room is open.
///
/// On Home that is the activity summary, which is the whole point of following
/// people: the moment you have nothing else to look at is the moment you want
/// to know where everyone is. Inside a space it stays the plain placeholder —
/// the summary spans every room, so scoping it to one space would either lie
/// about what it covers or repeat itself on every rail entry.
class _NoRoomView extends ConsumerWidget {
  const _NoRoomView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHome = ref.watch(selectedSpaceIdProvider) == kHomeSpaceId;
    return isHome ? const ActivityPage() : const EmptyChatView();
  }
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../activity/activity_page.dart';
import '../rooms/room_list_provider.dart';
import '../shell/selection_providers.dart';
import '../spaces/space_summary.dart';
import '../voice/call_controller_provider.dart';
import '../voice/call_view_provider.dart';
import '../voice/widgets/call_grid.dart';
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

    // The call takes the column, rather than sharing it with a shrunken
    // timeline. A grid of faces and screens is the thing being looked at while
    // it is up, and splitting the height between the two leaves both too small
    // to be worth having — a screen share unreadable, the conversation three
    // lines deep. `CallViewToggle` in the header is the way back.
    final controller = ref.watch(callControllerProvider);
    final timeline = ref.watch(timelinePreferredProvider);

    // The timeline subtree is built once and captured, not built inside the
    // `ListenableBuilder`: it holds the keyed `MessageList`, and rebuilding
    // that on every LiveKit event would throw its scroll position away several
    // times a second while somebody was talking.
    final conversation = ChatDropTarget(
      // Covers the message list and the composer, so a file can be dropped
      // anywhere in the chat area. Deliberately excludes the header — dropping
      // on a room title means nothing — and the call grid, whose native video
      // views swallow hit tests.
      roomId: roomId,
      roomName: header.name,
      child: Column(
        children: [
          Expanded(
            // Keyed by room so switching rooms rebuilds the list state (scroll
            // position, controller) instead of reusing the old one.
            child: MessageList(
              key: ValueKey(roomId),
              roomId: roomId,
              roomName: header.name,
            ),
          ),
          MessageComposer(roomId: roomId, roomName: header.name),
        ],
      ),
    );

    return Container(
      color: context.colors.timelineBackground,
      child: Column(
        children: [
          ChatHeader(header: header),
          Expanded(
            // `isInCallFor` lives on a `ChangeNotifier`, not in provider state,
            // so watching the provider would settle the answer once at build
            // and never move again — joining a call would leave the column on
            // the timeline until something unrelated rebuilt it.
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) =>
                  controller.isInCallFor(roomId) && !timeline
                  ? CallGrid(roomId: roomId)
                  : child!,
              child: conversation,
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

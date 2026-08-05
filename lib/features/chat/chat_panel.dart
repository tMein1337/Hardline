import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../rooms/room_list_provider.dart';
import '../shell/selection_providers.dart';
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
    if (roomId == null) return const EmptyChatView();

    final header = ref.watch(roomHeaderProvider(roomId));
    if (header == null) return const EmptyChatView();

    return Container(
      color: context.colors.chatBackground,
      child: Column(
        children: [
          ChatHeader(header: header),
          Expanded(
            // Keyed by room so switching rooms rebuilds the list state
            // (scroll position, controller) instead of reusing the old one.
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
  }
}

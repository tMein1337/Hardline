import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../../common/unread_badge.dart';
import '../../voice/call_controller_provider.dart';
import '../../voice/join_voice_action.dart';
import '../room_list_item.dart';

/// One row in the channel column.
///
/// Group rooms get Discord's `#` prefix; direct chats get the other person's
/// avatar instead, which is how Discord distinguishes DMs.
class RoomListTile extends StatelessWidget {
  const RoomListTile({
    super.key,
    required this.room,
    required this.selected,
    required this.onTap,
  });

  final RoomListItem room;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;

    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) {
        final background = selected
            ? colors.listItemSelected
            : hovered
            ? colors.listItemHover
            : Colors.transparent;

        // Unread rooms read brighter and bolder, like Discord.
        final showAsActive = selected || hovered || room.hasUnread;
        final labelStyle = showAsActive
            ? context.text.channelNameActive
            : context.text.channelName;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(metrics.rowRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (room.isDirect)
                  MxAvatar(
                    name: room.name,
                    seed: room.id,
                    mxcUri: room.avatarMxc,
                    size: 24,
                  )
                else
                  Icon(Icons.tag, size: 20, color: colors.textFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    room.name,
                    style: labelStyle.copyWith(
                      fontWeight: room.hasUnread
                          ? FontWeight.w600
                          : labelStyle.fontWeight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (room.isEncrypted) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.lock, size: 12, color: colors.textFaint),
                ],
                if (room.canStartVoice) ...[
                  const SizedBox(width: 4),
                  _JoinCallIcon(room: room, rowHovered: hovered),
                ],
                if (room.hasMention) ...[
                  const SizedBox(width: 6),
                  UnreadBadge(count: room.highlightCount),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The green phone that joins this channel's call.
///
/// Sits beside the encryption padlock rather than in the chat header so the
/// affordance is where the channel is — you can start a call without opening
/// the room first, which is how a voice channel is supposed to behave.
class _JoinCallIcon extends ConsumerWidget {
  const _JoinCallIcon({required this.room, required this.rowHovered});

  final RoomListItem room;

  /// Dimmed until the row is hovered. A saturated green on every channel at
  /// once would fight the unread badges for attention, which matter more.
  final bool rowHovered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final controller = ref.watch(callControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Already in this room's call: leaving lives in the voice footer, so a
        // second control here would be a green phone that does nothing.
        if (controller.isInCallFor(room.id)) return const SizedBox.shrink();

        return Hoverable(
          onTap: () => joinVoiceCall(
            context,
            ref,
            room.id,
            room.voiceJoinability,
          ),
          builder: (context, iconHovered) => Padding(
            // Widens the hit target without changing the row's height.
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Icon(
              Icons.call,
              size: 14,
              color: iconHovered || rowHovered
                  ? colors.voiceConnected
                  : colors.voiceConnected.withValues(alpha: 0.5),
            ),
          ),
        );
      },
    );
  }
}

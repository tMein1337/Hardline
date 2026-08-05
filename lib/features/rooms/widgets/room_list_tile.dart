import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../../common/unread_badge.dart';
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

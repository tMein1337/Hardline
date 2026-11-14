// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';
import '../../rooms/room_list_provider.dart';
import '../../rooms/widgets/room_manage_dialog.dart';
import '../../voice/widgets/call_view_toggle.dart';

/// Title bar of the chat column: room name, topic when there is one, the way
/// to the member list, and — in a room whose call we have joined — the switch
/// between the call and the conversation.
class ChatHeader extends StatelessWidget {
  const ChatHeader({super.key, required this.header});

  final RoomHeader header;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: context.metrics.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.timelineBackground,
        border: Border(bottom: BorderSide(color: colors.dividerStrong)),
      ),
      child: Row(
        children: [
          // Everything that describes the room, in a row of its own, so the
          // button after it is not one more thing competing for the width:
          // a long name with no topic still gets the whole of what is left.
          Expanded(
            child: Row(
              children: [
                Icon(
                  header.isDirect ? Icons.alternate_email : Icons.tag,
                  size: 22,
                  color: colors.textFaint,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    header.name,
                    style: context.text.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (header.isEncrypted) ...[
                  const SizedBox(width: 8),
                  // A padlock is only reassuring if you know what it claims.
                  // Saying it out loud also distinguishes "encrypted" from
                  // "verified", which the icon cannot.
                  Tooltip(
                    message: 'Messages in this room are end-to-end encrypted',
                    child: Icon(Icons.lock, size: 14, color: colors.success),
                  ),
                ],
                // Before the topic, and outside the `Expanded` that holds it:
                // a control that slides sideways as the topic is edited is a
                // control people stop trusting themselves to hit.
                CallViewToggle(roomId: header.id),
                if (header.topic.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Container(width: 1, height: 20, color: colors.divider),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Text(
                      header.topic.replaceAll('\n', ' '),
                      style: context.text.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Who is in here. At the far end, where it stays put whatever the
          // name and the topic do. Not for a direct chat: that has one other
          // person in it and they are already in the title.
          if (!header.isDirect)
            IconButton(
              key: const Key('chat_header_members'),
              tooltip: 'Members',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.group_outlined, color: colors.textMuted),
              onPressed: () => RoomManageDialog.show(
                context,
                header.id,
                section: RoomManageSection.members,
              ),
            ),
        ],
      ),
    );
  }
}

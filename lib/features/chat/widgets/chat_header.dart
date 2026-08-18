// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';
import '../../rooms/room_list_provider.dart';

/// Title bar of the chat column: room name, and topic when there is one.
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
            // A padlock is only reassuring if you know what it claims. Saying
            // it out loud also distinguishes "encrypted" from "verified",
            // which the icon cannot.
            Tooltip(
              message: 'Messages in this room are end-to-end encrypted',
              child: Icon(Icons.lock, size: 14, color: colors.success),
            ),
          ],
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
    );
  }
}

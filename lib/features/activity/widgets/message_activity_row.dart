// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/time_format.dart';
import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../activity_entries.dart';
import '../activity_navigation.dart';
import 'activity_section.dart';
import 'user_context_menu.dart';

/// One recent message, and the click that scrolls the channel to it.
class MessageActivityRow extends ConsumerWidget {
  const MessageActivityRow({super.key, required this.activity});

  final MessageActivity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return ActivityRow(
      avatar: MxAvatar(
        name: activity.displayName,
        seed: activity.userId,
        mxcUri: activity.avatarMxc,
        size: 32,
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(child: Text(activity.displayName)),
          const SizedBox(width: 6),
          Icon(Icons.tag, size: 12, color: colors.textFaint),
          Flexible(
            child: Text(
              activity.roomName,
              style: context.text.timestamp,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      // The preview is already one truncated line — see `previewOf` — so this
      // cannot grow the row however long the message was.
      subtitle: Text(
        activity.preview,
        style: context.text.subtitle,
      ),
      trailing: Text(
        formatRelativeTime(activity.timestamp.toLocal()),
        style: context.text.timestamp,
      ),
      tooltip: 'Show in #${activity.roomName}',
      onTap: () => jumpToMessage(ref, activity.roomId, activity.eventId),
      onSecondaryTap: () => UserContextMenu.show(
        context,
        userId: activity.userId,
        displayName: activity.displayName,
        avatarMxc: activity.avatarMxc,
      ),
    );
  }
}

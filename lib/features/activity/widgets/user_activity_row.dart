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

/// A followed person who is typing, or who typed recently.
class UserActivityRow extends ConsumerWidget {
  const UserActivityRow({super.key, required this.activity});

  final UserActivity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final eventId = activity.lastEventId;

    return ActivityRow(
      avatar: MxAvatar(
        name: activity.displayName,
        seed: activity.userId,
        mxcUri: activity.avatarMxc,
        size: 32,
      ),
      title: Text(activity.displayName),
      subtitle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tag, size: 12, color: colors.textFaint),
          const SizedBox(width: 2),
          Flexible(child: Text(activity.roomName)),
        ],
      ),
      // Jumps to their last message when there is one. Somebody who is only
      // typing has nothing to scroll to yet, so the row just opens the room.
      onTap: eventId == null
          ? () => openRoom(ref, activity.roomId)
          : () => jumpToMessage(ref, activity.roomId, eventId),
      onSecondaryTap: () => UserContextMenu.show(
        context,
        userId: activity.userId,
        displayName: activity.displayName,
        avatarMxc: activity.avatarMxc,
      ),
      trailing: _trailing(context),
    );
  }

  /// Typing wins over a timestamp: somebody mid-sentence is the more
  /// actionable fact, and showing both would put "typing… 4 min ago" on a row.
  Widget? _trailing(BuildContext context) {
    if (activity.isTyping) {
      return _TypingBadge(color: context.colors.voiceConnected);
    }
    // Only reachable for somebody who spoke inside the window — the provider
    // builds no row without one of the two — but a null here is a missing
    // trailing widget rather than a crash.
    final spokeAt = activity.lastSpokeAt;
    if (spokeAt == null) return null;
    return Text(
      formatRelativeTime(spokeAt.toLocal()),
      style: context.text.timestamp,
    );
  }
}

/// "typing…" — the one thing in this list that is happening right now.
class _TypingBadge extends StatelessWidget {
  const _TypingBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(context.metrics.rowRadius),
    ),
    child: Text(
      'typing…',
      style: context.text.timestamp.copyWith(color: color),
    ),
  );
}

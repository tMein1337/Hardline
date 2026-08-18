// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../../voice/call_controller_provider.dart';
import '../../voice/voice_joinability.dart';
import '../activity_entries.dart';
import '../activity_navigation.dart';
import 'activity_section.dart';
import 'user_context_menu.dart';

/// A followed person sitting in a call, and the button that puts you in it.
class VoiceActivityRow extends ConsumerWidget {
  const VoiceActivityRow({super.key, required this.activity});

  final VoiceActivity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final controller = ref.watch(callControllerProvider);

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
      // Opening the room is always safe; joining the call is not, so the row
      // navigates and the button joins.
      onTap: () => openRoom(ref, activity.roomId),
      onSecondaryTap: () => UserContextMenu.show(
        context,
        userId: activity.userId,
        displayName: activity.displayName,
        avatarMxc: activity.avatarMxc,
      ),
      // `isInCallFor` lives on a ChangeNotifier, not in provider state, so it
      // has to be read through a listenable — exactly as `_JoinCallIcon` in the
      // room list does.
      trailing: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.isInCallFor(activity.roomId)) {
            return _Tag(label: 'You are here', color: colors.voiceConnected);
          }
          if (!activity.canJoin) {
            return Tooltip(
              message: switch (activity.joinability) {
                VoiceJoinability.forbidden =>
                  'Calls are not enabled here and you cannot enable them',
                VoiceJoinability.notJoined => 'Join the room first',
                _ => '',
              },
              child: Icon(Icons.block, size: 16, color: colors.textFaint),
            );
          }
          return TextButton.icon(
            onPressed: () => joinFromActivity(
              context,
              ref,
              activity.roomId,
              activity.joinability,
            ),
            icon: Icon(Icons.call, size: 16, color: colors.voiceConnected),
            label: Text(
              // The glyph is identical whether joining is one click or needs
              // the room's power levels changed first. Saying which is the only
              // way to know before pressing it.
              activity.joinability == VoiceJoinability.needsEnabling
                  ? 'Enable & join'
                  : 'Join',
              style: context.text.buttonLabel.copyWith(
                color: colors.voiceConnected,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(context.metrics.rowRadius),
    ),
    child: Text(
      label,
      style: context.text.timestamp.copyWith(color: color),
    ),
  );
}

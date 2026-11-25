// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../../common/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../../common/unread_badge.dart';
import '../../voice/call_controller_provider.dart';
import '../../voice/join_voice_action.dart';
import '../../voice/voice_joinability.dart';
import '../../activity/widgets/user_context_menu.dart';
import 'room_manage_dialog.dart';
import '../../voice/voice_participants_provider.dart';
import '../room_list_item.dart';

/// One row in the channel column.
///
/// Group rooms get a `#` prefix, which is what a Matrix room alias literally
/// starts with; direct chats get the other person's avatar instead.
class RoomListTile extends StatelessWidget {
  const RoomListTile({
    super.key,
    required this.room,
    required this.selected,
    required this.onTap,
    this.onDoubleTap,
  });

  final RoomListItem room;
  final bool selected;
  final VoidCallback onTap;

  /// Joins the call, when the setting for it is on.
  ///
  /// Null otherwise, and that is load-bearing rather than tidy: a
  /// `GestureDetector` holding both gestures delays every single tap by the
  /// double-tap timeout, so passing a handler unconditionally would make
  /// switching rooms feel slow for everybody who never asked for this.
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;

    return Hoverable(
      key: Key('room_tile_${room.id}'),
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      // A channel manages itself; a direct chat is really a person, so it
      // opens the person. Both are right-click, because both are "tell me
      // about this row" — it is the row that differs, not the gesture.
      //
      // The room dialog is still reachable for a chat: `UserContextMenu` has
      // a way through to it, so leaving one is not stranded behind knowing to
      // right-click somewhere else.
      onSecondaryTap: room.directUserId == null
          ? () => RoomManageDialog.show(context, room.id)
          : () => UserContextMenu.show(
              context,
              userId: room.directUserId!,
              displayName: room.name,
              avatarMxc: room.avatarMxc,
              roomId: room.id,
            ),
      builder: (context, hovered) {
        final background = selected
            ? colors.listItemSelected
            : hovered
            ? colors.listItemHover
            : Colors.transparent;

        // Unread rooms read brighter and bolder.
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
                  AppTooltip(
                    message: 'End-to-end encrypted',
                    child: Icon(Icons.lock, size: 12, color: colors.textFaint),
                  ),
                ],
                const SizedBox(width: 4),
                _JoinCallIcon(room: room, rowHovered: hovered),
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
///
/// **Shown for two different reasons**, and it used to be shown for only the
/// first:
///
///  1. We may start a call here — `RoomListItem.canStartVoice`, which is a
///     pure power-level question.
///  2. A call is already running here, whatever our power levels say.
///
/// The second is why this changed. `joinabilityOf` answers `forbidden` for an
/// ordinary member of a room with Synapse's default `state_default: 50`, which
/// is the *normal* first answer rather than an edge case — so somebody else
/// starting a call left the row looking exactly like a text channel, with no
/// glyph and nothing to click. The participants did appear underneath the row,
/// which made it worse: visibly a call, with no way in and no explanation.
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

    // Live from sync: this is the same provider the participant list under the
    // row is built from, so the glyph and the faces cannot disagree.
    final live = ref.watch(voiceParticipantsProvider(room.id)).isNotEmpty;
    if (!room.canStartVoice && !live) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Already in this room's call: leaving lives in the voice footer, so a
        // second control here would be a green phone that does nothing.
        if (controller.isInCallFor(room.id)) return const SizedBox.shrink();

        return Hoverable(
          onTap: () =>
              joinVoiceCall(context, ref, room.id, room.voiceJoinability),
          builder: (context, iconHovered) => AppTooltip(
            // The glyph is identical whether joining is one click, needs the
            // room's power levels changed first, or is not open to us at all.
            // Saying which is the only way to know before pressing it.
            message: switch (room.voiceJoinability) {
              VoiceJoinability.joinable =>
                live ? 'Join the call in progress' : 'Join voice call',
              VoiceJoinability.needsEnabling =>
                'Enable calls in this channel, then join',
              VoiceJoinability.forbidden =>
                'A call is running, but only moderators can join it here',
              VoiceJoinability.notJoined => 'Join the room first',
            },
            child: Padding(
              // Widens the hit target without changing the row's height.
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Icon(
                Icons.call,
                size: 14,
                // A call already in progress is worth seeing without hovering
                // for it; an empty channel we merely *could* call in is not.
                color: live || iconHovered || rowHovered
                    ? colors.voiceConnected
                    : colors.voiceConnected.withValues(alpha: 0.5),
              ),
            ),
          ),
        );
      },
    );
  }
}

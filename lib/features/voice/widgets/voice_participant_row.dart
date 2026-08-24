// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../call_controller_provider.dart';
import '../voice_participant.dart';
import '../voice_prefs_controller.dart';
import 'speaking_ring.dart';
import 'user_audio_menu.dart';

/// One person inside a channel's voice call, drawn under the channel row.
///
/// Indented past the channel's `#` glyph so the nesting reads at a glance, the
/// way call members are listed beneath the room they are in.
class VoiceParticipantRow extends ConsumerWidget {
  const VoiceParticipantRow({
    super.key,
    required this.roomId,
    required this.participant,
  });

  /// The channel this row is listed under.
  ///
  /// Only the speaking ring needs it, and only to refuse to light up for a
  /// call other than the one we joined.
  final String roomId;

  final VoiceParticipant participant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final metrics = context.metrics;
    final audio = ref.watch(voicePrefsProvider).forUser(participant.userId);

    // The badge shows a gain only when it is unambiguous: one connected device
    // with a non-default volume. Someone on two devices with two different
    // gains has no single number to show, and picking one arbitrarily would be
    // worse than showing none — the menu spells it out per device instead.
    final adjustedVolume = participant.deviceIds.length == 1
        ? switch (audio.forDevice(participant.deviceIds.single).micVolume) {
            1.0 => null,
            final volume => volume,
          }
        : null;

    return Hoverable(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered) {
        return GestureDetector(
          // Right-click opens per-user volume. Left-click is
          // deliberately left free — the row is not a navigation target.
          onSecondaryTap: () => UserAudioMenu.show(context, participant),
          child: Padding(
            // Extra left inset over RoomListTile's 8, so the row sits under the
            // channel name rather than under its icon.
            padding: const EdgeInsets.only(
              left: 30,
              right: 8,
              top: 1,
              bottom: 1,
            ),
            child: Container(
              height: 26,
              decoration: BoxDecoration(
                color: hovered
                    ? colors.voiceParticipantRowHover
                    : colors.voiceParticipantRow,
                borderRadius: BorderRadius.circular(metrics.rowRadius),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Opacity(
                    // Someone silenced locally reads as dimmed rather than
                    // hidden: they are still in the channel, you just cannot
                    // hear them.
                    //
                    // The ring dims with them rather than staying bright. It is
                    // still perfectly legible at this opacity, and the two
                    // facts belong together: they are talking, and you have
                    // chosen not to hear it.
                    opacity: audio.locallyMuted ? 0.45 : 1,
                    child: SpeakingRing(
                      userId: participant.userId,
                      // Scoped to this channel: somebody in two calls at once
                      // is listed under both, and only the one we joined can
                      // say whether they are talking.
                      roomId: roomId,
                      size: 18,
                      child: MxAvatar(
                        name: participant.displayName,
                        seed: participant.userId,
                        mxcUri: participant.avatarMxc,
                        size: 18,
                      ),
                    ),
                  ),
                  // 6 rather than 8: the ring reserves 2px of its own on each
                  // side, so the optical gap to the name is unchanged from
                  // before there was a ring.
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      participant.displayName,
                      style: context.text.subtitle.copyWith(
                        color: audio.locallyMuted
                            ? colors.textFaint
                            : participant.isSelf
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Locally muted, i.e. our own choice — distinct from the
                  // person having muted their own microphone, which does not
                  // reach room state and so cannot be shown here at all.
                  if (audio.locallyMuted) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      // Spelling out whose decision this was: the icon looks
                      // identical to "they muted themselves", which is a
                      // different fact and not one we can even observe.
                      message: 'Muted for you only',
                      child: Icon(
                        Icons.volume_off,
                        size: 13,
                        color: colors.voiceMutedIcon,
                      ),
                    ),
                  ] else if (adjustedVolume != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${(adjustedVolume * 100).round()}%',
                      style: context.text.timestamp,
                    ),
                  ],
                  _ScreenShareBadge(
                    roomId: roomId,
                    userId: participant.userId,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The "sharing their screen" badge, for the call we are actually in.
///
/// Its own widget because the fact lives on a `ChangeNotifier` rather than in
/// provider state — the same reason `voice_activity_row.dart` reads
/// `isInCallFor` through a listenable. Scoping the rebuild to the badge keeps
/// LiveKit's event rate out of the row, and out of the sidebar behind it.
///
/// Draws nothing for a call we have not joined. That is not a gap to fill
/// later: a screen share is a LiveKit publication and nothing about it reaches
/// Matrix room state, so from outside the call there is nothing to know.
class _ScreenShareBadge extends ConsumerWidget {
  const _ScreenShareBadge({required this.roomId, required this.userId});

  final String roomId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(callControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isInCallFor(roomId) ||
            !controller.isScreenSharing(userId)) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(
            message: 'Sharing their screen',
            child: Icon(
              Icons.screen_share,
              size: 14,
              color: context.colors.voiceControlIconActive,
            ),
          ),
        );
      },
    );
  }
}

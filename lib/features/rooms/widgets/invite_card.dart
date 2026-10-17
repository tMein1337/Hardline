// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../../shell/selection_providers.dart';
import '../../spaces/space_summary.dart';
import '../invites_provider.dart';

/// One pending invitation, with the two things that can be done about it.
///
/// Both answers are offered, and neither is the default. An invitation is a
/// request from another person; a client that made accepting the easy path
/// would be answering on the user's behalf.
class InviteCard extends ConsumerStatefulWidget {
  const InviteCard({super.key, required this.invite});

  final RoomInvite invite;

  @override
  ConsumerState<InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<InviteCard> {
  bool _busy = false;
  String? _error;

  Future<void> _answer({required bool accept}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final actions = ref.read(inviteActionsProvider);
    final invite = widget.invite;

    try {
      if (accept) {
        await actions.accept(invite.roomId);
        if (!mounted) return;
        // Opening what was just accepted, so the answer visibly leads
        // somewhere. A space becomes the selected rail entry; a room becomes
        // the open room in whichever list it lands in.
        if (invite.isSpace) {
          ref.read(selectedSpaceIdProvider.notifier).select(invite.roomId);
        } else {
          ref
              .read(selectedRoomIdsProvider.notifier)
              .select(spaceId: kHomeSpaceId, roomId: invite.roomId);
        }
      } else {
        await actions.decline(invite.roomId);
      }
      // Nothing is set on success: the room's membership changed, so the sync
      // tick drops this card from the list and this State goes with it.
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _describe(error);
        });
      }
    }
  }

  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('M_FORBIDDEN')) {
      return 'That invitation is no longer valid — it may have been '
          'withdrawn.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final invite = widget.invite;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.elevatedSurface,
        borderRadius: BorderRadius.circular(context.metrics.rowRadius * 3),
        // Accented, because this is the one thing in the column that is
        // waiting on an answer rather than simply being there.
        border: Border.all(color: colors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MxAvatar(
                name: invite.name,
                seed: invite.roomId,
                mxcUri: invite.avatarMxc,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.name,
                      style: context.text.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _subtitle(invite),
                      style: context.text.timestamp,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (invite.isEncrypted)
                Icon(Icons.lock, size: 12, color: colors.textFaint),
            ],
          ),
          if (_error case final message?) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: context.text.timestamp.copyWith(color: colors.danger),
            ),
          ],
          const SizedBox(height: 6),
          if (_busy)
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => _answer(accept: false),
                    child: Text(
                      'Decline',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _answer(accept: true),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Who sent it, which is the part of the decision worth showing.
  static String _subtitle(RoomInvite invite) {
    final kind = invite.isSpace ? 'Space invitation' : 'Invitation';
    final who = invite.inviterName;
    return who == null ? kind : '$kind from $who';
  }
}

/// The same card, as a dialog.
///
/// For the rail, which is 64 pixels wide and has nowhere to put two buttons
/// and a sentence about who sent the invitation.
class InviteDialog extends StatelessWidget {
  const InviteDialog({super.key, required this.invite});

  final RoomInvite invite;

  static Future<void> show(BuildContext context, RoomInvite invite) =>
      showDialog(
        context: context,
        builder: (_) => InviteDialog(invite: invite),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.floatingSurface,
      title: Text('Invitation', style: context.text.title),
      // The card closes itself by disappearing when the membership changes,
      // and the dialog has to follow it out.
      content: SizedBox(width: 360, child: _DismissOnAnswer(invite: invite)),
    );
  }
}

/// Closes the dialog once the invitation it is about is gone.
class _DismissOnAnswer extends ConsumerWidget {
  const _DismissOnAnswer({required this.invite});

  final RoomInvite invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stillPending = ref
        .watch(spaceInvitesProvider)
        .items
        .any((pending) => pending.roomId == invite.roomId);

    if (!stillPending) {
      // After the frame: this runs during a build, and popping a route from
      // inside one is an error.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }

    return InviteCard(invite: invite);
  }
}

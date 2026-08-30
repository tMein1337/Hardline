// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../common/hoverable.dart';
import '../common/mx_avatar.dart';
import '../rooms/invites_provider.dart';
import '../rooms/widgets/invite_card.dart';
import '../shell/selection_providers.dart';
import 'space_list_provider.dart';
import 'space_summary.dart';
import 'widgets/create_room_dialog.dart';
import 'widgets/join_space_dialog.dart';
import '../rooms/widgets/room_manage_dialog.dart';
import 'widgets/space_rail_button.dart';

/// The leftmost column: Home, then one icon per joined space.
class SpaceRail extends ConsumerWidget {
  const SpaceRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final metrics = context.metrics;
    final spaces = ref.watch(spaceListProvider);
    final selectedId = ref.watch(selectedSpaceIdProvider);
    // Below the spaces and above the create tile: an invitation is a space
    // that is not yours yet, so it belongs where a space would be, without
    // being mixed in among the ones you are actually in.
    final invites = ref.watch(spaceInvitesProvider).items;

    return Container(
      width: metrics.railWidth,
      color: colors.spaceRail,
      child: ScrollConfiguration(
        // The rail is narrow; a scrollbar here would crowd the icons.
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 12),
          // The spaces, then any pending invitations, then one past the end
          // for the "create a space" tile — a rail that can only ever show
          // spaces somebody else made is a rail that cannot be started from.
          itemCount: spaces.length + invites.length + 1,
          separatorBuilder: (context, index) {
            // Home is separated from real spaces by a rule.
            if (index != 0) return const SizedBox(height: 8);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Divider(color: colors.dividerStrong, height: 2),
            );
          },
          itemBuilder: (context, index) {
            if (index < spaces.length) {
              final space = spaces[index];
              return SpaceRailButton(
                space: space,
                selected: space.id == selectedId,
                onTap: () => _onTap(ref, space.id, selectedId),
                // Home is a bucket for rooms belonging to no space, not a
                // room of its own — there is nothing to rename, invite to or
                // delete.
                onSecondaryTap: space.isHome
                    ? null
                    : () => RoomManageDialog.show(context, space.id),
              );
            }

            final inviteIndex = index - spaces.length;
            if (inviteIndex < invites.length) {
              return _SpaceInviteButton(invite: invites[inviteIndex]);
            }

            return const _CreateSpaceButton();
          },
        ),
      ),
    );
  }

  /// Selects [spaceId], or goes back to the activity summary when Home is
  /// tapped while Home is already open.
  ///
  /// Without the second half, tapping Home from inside a direct message did
  /// **nothing at all**: it set `selectedSpaceId` to the value it already held,
  /// Riverpod short-circuited on `==`, and the DM stayed on screen. The
  /// activity page shows only when Home has no room selected, and nothing ever
  /// cleared that — so the one screen the app opens on became unreachable for
  /// the rest of the session.
  ///
  /// Only Home behaves this way *here*. A space rail button is a place, and
  /// tapping the place you are already in should not throw away which channel
  /// you had open there — where Home's screen is the activity summary, which
  /// has no channel to lose.
  ///
  /// Spaces have a screen of their own too, and reaching it is what
  /// `RoomListHeader`'s title is for: the rail says "go to this space, where I
  /// left it", the name says "show me this space". Two affordances because
  /// they are two different intentions, and folding them into one would mean
  /// losing your place every time you reached for the rail.
  void _onTap(WidgetRef ref, String spaceId, String selectedId) {
    if (spaceId == kHomeSpaceId && selectedId == kHomeSpaceId) {
      ref.read(selectedRoomIdsProvider.notifier).clear(kHomeSpaceId);
      return;
    }
    ref.read(selectedSpaceIdProvider.notifier).select(spaceId);
  }
}

/// The last tile on the rail: get another space.
///
/// Drawn like a rail tile rather than as a floating action button, because it
/// is one more place in the same column — the shape of the rail is what says
/// what it is for.
///
/// Opens a chooser rather than going straight to one of them: there are two
/// ways to end up with a space you did not have, and picking one on somebody's
/// behalf would hide the other.
class _CreateSpaceButton extends StatelessWidget {
  const _CreateSpaceButton();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;

    return Tooltip(
      message: 'Add a space',
      child: Hoverable(
        onTap: () => _AddSpaceDialog.show(context),
        builder: (context, hovered) => SizedBox(
          height: metrics.railIconSize + 8,
          child: Center(
            child: Container(
              width: metrics.railIconSize,
              height: metrics.railIconSize,
              decoration: BoxDecoration(
                color: hovered ? colors.railHover : colors.railIdle,
                borderRadius: BorderRadius.circular(metrics.railIconRadius),
              ),
              child: Icon(
                Icons.add,
                size: 20,
                color: hovered ? colors.accent : colors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A space somebody has invited this account to.
///
/// Drawn as the space it would become, ringed in the accent colour and badged,
/// so it reads as "not yours yet" rather than as one more space you are in.
/// Tapping opens the invitation, because 64 pixels of rail has nowhere to put
/// two buttons and the name of whoever sent it.
class _SpaceInviteButton extends StatelessWidget {
  const _SpaceInviteButton({required this.invite});

  final RoomInvite invite;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;

    return Tooltip(
      message: invite.inviterName == null
          ? 'Invitation to ${invite.name}'
          : '${invite.inviterName} invited you to ${invite.name}',
      child: Hoverable(
        onTap: () => InviteDialog.show(context, invite),
        builder: (context, hovered) => SizedBox(
          height: metrics.railIconSize + 8,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: metrics.railIconSize,
                  height: metrics.railIconSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(metrics.railIconRadius),
                    border: Border.all(
                      color: hovered
                          ? colors.accent
                          : colors.accent.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      metrics.railIconRadius - 2,
                    ),
                    child: MxAvatar(
                      name: invite.name,
                      seed: invite.roomId,
                      mxcUri: invite.avatarMxc,
                      size: metrics.railIconSize - 4,
                    ),
                  ),
                ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: colors.spaceRail,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.mail_outline,
                      size: 12,
                      color: colors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Create one, or join one that exists.
///
/// Two buttons and a sentence each, rather than a menu: the app has no popup
/// menus anywhere (see `ThemeLibraryCard`), and the difference between making
/// a space and joining somebody else's is worth a sentence.
class _AddSpaceDialog extends StatelessWidget {
  const _AddSpaceDialog();

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, builder: (_) => const _AddSpaceDialog());

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Add a space', style: context.text.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Choice(
              icon: Icons.add_circle_outline,
              title: 'Create a space',
              blurb: 'A new space of your own, to put rooms in.',
              onTap: () {
                Navigator.of(context).pop();
                CreateRoomDialog.show(context, kind: CreateKind.space);
              },
            ),
            const SizedBox(height: 8),
            _Choice(
              icon: Icons.travel_explore,
              title: 'Join a space',
              blurb: 'Somebody gave you an address like #gaming:example.org.',
              onTap: () {
                Navigator.of(context).pop();
                JoinSpaceDialog.show(context);
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Invitations arrive on the rail on their own — there is nothing '
              'to do here for one of those.',
              style: context.text.timestamp,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.blurb,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String blurb;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hovered ? colors.listItemHover : colors.elevatedSurface,
          borderRadius: BorderRadius.circular(context.metrics.rowRadius * 3),
          border: Border.all(color: hovered ? colors.accent : colors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.username),
                  Text(blurb, style: context.text.timestamp),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

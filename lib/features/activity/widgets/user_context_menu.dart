// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/services.dart';

import '../../../core/providers/own_profile_provider.dart';
import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../../rooms/widgets/room_manage_dialog.dart';
import '../activity_prefs_controller.dart';
import '../shared_rooms_provider.dart';

/// Who somebody is, from anywhere their name or face is drawn.
///
/// A dialog rather than a popup menu so it can show who it is talking about:
/// the same display name can belong to two people, and following the wrong one
/// is silent — the summary simply reports somebody you did not mean. That is
/// also why the user id is shown in full and can be copied: it is the only
/// part of an identity that is actually unique.
///
/// Deliberately a `ConsumerWidget` behind a static `show`, so the callers
/// (`MessageTile`, which is a plain `StatelessWidget`) need no `WidgetRef` of
/// their own.
class UserContextMenu extends ConsumerWidget {
  const UserContextMenu({
    super.key,
    required this.userId,
    required this.displayName,
    this.avatarMxc,
    this.roomId,
  });

  final String userId;
  final String displayName;
  final String? avatarMxc;

  /// The direct chat this person was opened from, when there is one.
  ///
  /// A chat row is a person *and* a room, and right-click can only mean one of
  /// them. It means the person — but leaving the room then has nowhere to be
  /// reached from, so the way through to it is offered here.
  final String? roomId;

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required String displayName,
    String? avatarMxc,
    String? roomId,
  }) => showDialog(
    context: context,
    builder: (context) => UserContextMenu(
      userId: userId,
      displayName: displayName,
      avatarMxc: avatarMxc,
      roomId: roomId,
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefs = ref.watch(activityPrefsProvider);
    final isSelf = ref.watch(ownUserIdProvider) == userId;
    final following = prefs.isFollowing(userId);

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Row(
        children: [
          MxAvatar(
            name: displayName,
            seed: userId,
            mxcUri: avatarMxc,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: context.text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        userId,
                        style: context.text.timestamp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy user ID',
                      iconSize: 14,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.copy_all_outlined,
                        color: colors.textFaint,
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: userId));
                        if (!context.mounted) return;
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(content: Text('User ID copied.')),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSelf
                  ? 'This is you. Following yourself would fill your own '
                        'activity summary with things you already know.'
                  : following
                  ? 'Their calls and messages show up in the activity summary '
                        'on the Home screen.'
                  : 'Following someone puts their calls and recent messages '
                        'on the Home screen. Nothing is sent anywhere — this '
                        'is a note to yourself.',
              style: context.text.subtitle,
            ),
            if (!isSelf) ...[
              const SizedBox(height: 16),
              _SharedRooms(userId: userId),
            ],
          ],
        ),
      ),
      actions: [
        if (roomId case final id?)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              RoomManageDialog.show(context, id);
            },
            child: Text(
              'Chat settings',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: colors.textMuted)),
        ),
        if (!isSelf)
          FilledButton(
            onPressed: () async {
              await ref
                  .read(activityPrefsProvider.notifier)
                  .toggleFollow(userId);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(following ? 'Unfollow' : 'Follow'),
          ),
      ],
    );
  }
}

/// Where else you and this person both are.
///
/// Capped and counted rather than listed in full: somebody you share thirty
/// rooms with would otherwise turn a dialog into a scroll.
class _SharedRooms extends ConsumerWidget {
  const _SharedRooms({required this.userId});

  static const _shown = 5;

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(sharedRoomsProvider(userId));
    if (rooms.isEmpty) return const SizedBox.shrink();

    final extra = rooms.length - _shown;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ALSO IN', style: context.text.fieldLabel),
        const SizedBox(height: 4),
        for (final name in rooms.take(_shown))
          Text(
            name,
            style: context.text.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (extra > 0)
          Text(
            'and $extra more',
            style: context.text.timestamp,
          ),
      ],
    );
  }
}

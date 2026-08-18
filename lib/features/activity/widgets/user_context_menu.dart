// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/own_profile_provider.dart';
import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../activity_prefs_controller.dart';

/// What right-clicking somebody's name or avatar in the chat offers.
///
/// A dialog rather than a popup menu so it can show who it is talking about:
/// the same display name can belong to two people, and following the wrong one
/// is silent — the summary simply reports somebody you did not mean.
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
  });

  final String userId;
  final String displayName;
  final String? avatarMxc;

  static Future<void> show(
    BuildContext context, {
    required String userId,
    required String displayName,
    String? avatarMxc,
  }) => showDialog(
    context: context,
    builder: (context) => UserContextMenu(
      userId: userId,
      displayName: displayName,
      avatarMxc: avatarMxc,
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
                Text(
                  userId,
                  style: context.text.timestamp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Text(
          isSelf
              ? 'This is you. Following yourself would fill your own activity '
                    'summary with things you already know.'
              : following
              ? 'Their calls and messages show up in the activity summary on '
                    'the Home screen.'
              : 'Following someone puts their calls and recent messages on the '
                    'Home screen. Nothing is sent anywhere — this is a note to '
                    'yourself.',
          style: context.text.subtitle,
        ),
      ),
      actions: [
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

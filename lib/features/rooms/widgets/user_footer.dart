// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/own_profile_provider.dart';
import '../../../theme/theme_context.dart';
import '../../accounts/account_entry.dart';
import '../../common/mx_avatar.dart';
import '../../settings/settings_screen.dart';
import '../../voice/widgets/speaking_ring.dart';

/// The signed-in user's strip at the bottom of the channel column.
///
/// The gear is the only button here. Signing out moved into settings when the
/// unified screen landed: it sat one pixel from the settings icon, is
/// irreversible, and a footer this small is the wrong place for it, so it is
/// not in
/// the footer either.
class UserFooter extends ConsumerWidget {
  const UserFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final userId = ref.watch(ownUserIdProvider);
    final profile = ref.watch(ownProfileProvider).value;

    final displayName = profile?.displayName ?? localpartOf(userId);

    return Container(
      height: 52,
      color: colors.floatingSurface,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Your own avatar rings while your microphone is picking you up.
          //
          // The participant list already shows it, but only for whoever is
          // scrolled into view in the sidebar — this strip is on screen for as
          // long as the app is, which is what makes it the honest answer to
          // "am I actually being heard". No ring while muted is the same
          // answer, correctly given.
          //
          // No `roomId`: this asks about the call we are in, whichever room
          // that is, because the footer is not tied to one.
          SpeakingRing(
            userId: userId,
            size: 32,
            child: MxAvatar(
              name: displayName,
              seed: userId,
              mxcUri: profile?.avatarUrl?.toString(),
              size: 32,
            ),
          ),
          // 6 rather than 8: the ring reserves 2px of its own.
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: context.text.username.copyWith(
                    fontSize: context.text.sized(14),
                  ),
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
          IconButton(
            tooltip: 'Settings',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: colors.textMuted,
            onPressed: () => SettingsScreen.open(context),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
    );
  }
}

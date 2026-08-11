import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/own_profile_provider.dart';
import '../../../theme/theme_context.dart';
import '../../accounts/account_entry.dart';
import '../../common/mx_avatar.dart';
import '../../settings/settings_screen.dart';

/// The signed-in user's strip at the bottom of the channel column.
///
/// The gear is the only button here. Signing out moved into settings when the
/// unified screen landed: it sat one pixel from the settings icon, is
/// irreversible, and Discord — whose layout this follows — does not put it in
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
          MxAvatar(
            name: displayName,
            seed: userId,
            mxcUri: profile?.avatarUrl?.toString(),
            size: 32,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: context.text.username.copyWith(fontSize: 14),
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

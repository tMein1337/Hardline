import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/own_profile_provider.dart';
import '../../../theme/theme_context.dart';
import '../../auth/session_controller.dart';
import '../../common/mx_avatar.dart';
import '../../voice/widgets/voice_settings_dialog.dart';

/// The signed-in user's strip at the bottom of the channel column.
class UserFooter extends ConsumerWidget {
  const UserFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final userId = ref.watch(ownUserIdProvider);
    final profile = ref.watch(ownProfileProvider).value;
    final signingOut = ref.watch(sessionControllerProvider);

    final displayName = profile?.displayName ?? _localpart(userId);

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
            tooltip: 'Voice settings',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: colors.textMuted,
            onPressed: () => VoiceSettingsDialog.show(context),
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Sign out',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: colors.textMuted,
            onPressed: signingOut
                ? null
                : () => ref.read(sessionControllerProvider.notifier).signOut(),
            icon: signingOut
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textMuted,
                    ),
                  )
                : const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }

  static String _localpart(String userId) =>
      userId.startsWith('@') ? userId.substring(1).split(':').first : userId;
}

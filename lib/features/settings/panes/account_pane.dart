import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/own_profile_provider.dart';
import '../../../theme/theme_context.dart';
import '../../accounts/account_actions.dart';
import '../../accounts/account_entry.dart';
import '../../accounts/account_registry.dart';
import '../../accounts/active_client.dart';
import '../../auth/login_screen.dart';
import '../../chat/attachments/attachment_picker_source.dart';
import '../../common/mx_avatar.dart';
import '../profile_controller.dart';
import '../settings_screen.dart';
import '../widgets/settings_layout.dart';
import '../widgets/text_prompt.dart';

/// Who you are signed in as, what that looks like to other people, and which
/// other accounts this computer remembers.
class AccountPane extends ConsumerWidget {
  const AccountPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(ownUserIdProvider);
    final profile = ref.watch(ownProfileProvider).value;
    final active = ref.watch(activeClientProvider);
    final accounts = ref.watch(accountRegistryProvider);
    final busy = ref.watch(profileControllerProvider).isLoading;

    final others = [
      for (final entry in accounts.entries)
        if (entry.storageKey != active.storageKey) entry,
    ];

    return SettingsPane(
      title: 'My Account',
      children: [
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  MxAvatar(
                    name: profile?.displayName ?? localpartOf(userId),
                    seed: userId,
                    mxcUri: profile?.avatarUrl?.toString(),
                    size: 72,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?.displayName ?? localpartOf(userId),
                          style: context.text.title.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        SelectableText(userId, style: context.text.subtitle),
                        if (active.client.homeserver?.host case final host?)
                          Text(host, style: context.text.timestamp),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _pickAvatar(context, ref),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Change avatar'),
                  ),
                  const SizedBox(width: 8),
                  if (profile?.avatarUrl != null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : ref
                                .read(profileControllerProvider.notifier)
                                .removeAvatar,
                      child: Text(
                        'Remove',
                        style: TextStyle(color: context.colors.textMuted),
                      ),
                    ),
                  const Spacer(),
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SettingsDivider(),
              SettingsRow(
                title: 'Display name',
                subtitle: profile?.displayName ?? 'Not set',
                trailing: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _editDisplayName(
                          context,
                          ref,
                          profile?.displayName ?? '',
                        ),
                  child: const Text('Edit'),
                ),
              ),
            ],
          ),
        ),

        if (ref.watch(profileControllerProvider) case AsyncError(:final error))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Could not save that: $error',
              style: context.text.subtitle.copyWith(
                color: context.colors.danger,
              ),
            ),
          ),

        const SizedBox(height: 32),
        const SettingsLabel('Accounts on this computer'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in others) ...[
                _AccountRow(entry: entry),
                const SettingsDivider(),
              ],
              if (others.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Only this account is signed in. Adding another keeps both '
                    'signed in — switching between them does not ask for a '
                    'password again.',
                    style: context.text.subtitle,
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => LoginScreen.addAccount(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add an account'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
        const SettingsLabel('Session'),
        SettingsCard(
          child: SettingsRow(
            title: 'Log out',
            subtitle:
                'Signs this account out and removes its history from this '
                'computer.',
            trailing: TextButton(
              onPressed: () async {
                if (!await confirmSignOut(context)) return;
                if (!context.mounted) return;
                Navigator.of(context).pop();
                await ref.read(accountActionsProvider.notifier).signOutActive();
              },
              child: Text(
                'Log out',
                style: TextStyle(color: context.colors.danger),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAvatar(BuildContext context, WidgetRef ref) async {
    final path = await pickImagePath();
    if (path == null) return;
    await ref.read(profileControllerProvider.notifier).setAvatarFromPath(path);
  }

  Future<void> _editDisplayName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final name = await promptForText(
      context,
      title: 'Display name',
      hint: 'How other people see you',
      initial: current,
    );
    if (name == null) return;
    await ref.read(profileControllerProvider.notifier).setDisplayName(name);
  }
}

/// One remembered account that is not the live one.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.entry});

  final AccountEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsRow(
      leading: MxAvatar(
        name: entry.label,
        seed: entry.userId,
        mxcUri: entry.avatarUrl,
        size: 40,
      ),
      title: entry.label,
      subtitle: entry.userId,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
            onPressed: () async {
              // Pop first: switching tears down every provider the settings
              // screen is reading, and the route would be rebuilding against a
              // disposed client while it animates away.
              Navigator.of(context).pop();
              await ref
                  .read(accountActionsProvider.notifier)
                  .switchTo(entry.storageKey);
            },
            child: const Text('Switch'),
          ),
          IconButton(
            tooltip: 'Sign out of ${entry.label}',
            onPressed: () async {
              if (!await confirmSignOut(context, account: entry.label)) return;
              await ref
                  .read(accountActionsProvider.notifier)
                  .signOutOther(entry.storageKey);
            },
            icon: Icon(Icons.logout, size: 18, color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}

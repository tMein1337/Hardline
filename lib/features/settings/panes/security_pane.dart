// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../device_encryption.dart';
import '../security_prefs.dart';
import '../widgets/passphrase_prompt.dart';
import '../widgets/settings_layout.dart';

/// The safeguards that stand between a stray click and something leaving the
/// app, and the lock on what it has already written down.
///
/// Separate from the sessions pane, which is about *this account* — its devices,
/// its keys, who is verified. Everything here is about this installation and
/// applies whoever is signed in.
class SecurityPane extends ConsumerWidget {
  const SecurityPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(securityPrefsProvider);

    return SettingsPane(
      title: 'Security',
      description:
          'How careful the app is with things that leave it, and with what it '
          'keeps. These apply to this installation, not to one account.',
      children: [
        const SettingsLabel('Links'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.confirmLinks,
                title: Text(
                  'Ask before opening a link',
                  style: context.text.messageBody,
                ),
                subtitle: Text(
                  'A link in a message was written by somebody else, and '
                  'following it leaves Hardline and tells that address you '
                  'were here. With this on, clicking one shows where it goes '
                  'and waits for an answer.',
                  style: context.text.timestamp,
                ),
                onChanged: (value) => ref
                    .read(securityPrefsProvider.notifier)
                    .setConfirmLinks(value),
              ),
              const SettingsDivider(),
              Text(
                'A link to a room or a message you are already in opens here '
                'and never asks — it does not leave the app. Only http and '
                'https links in a message are clickable at all; anything else '
                'stays as plain text.',
                style: context.text.timestamp,
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        const SettingsLabel('Data on this device'),
        const _DeviceEncryptionCard(),
      ],
    );
  }
}

/// Encrypting the sqlite stores this installation keeps.
class _DeviceEncryptionCard extends ConsumerWidget {
  const _DeviceEncryptionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(deviceEncryptionEnabledProvider);
    final status = ref.watch(deviceEncryptionProvider);
    final controller = ref.read(deviceEncryptionProvider.notifier);

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            title: Text(
              'Encrypt the data stored on this device',
              style: context.text.messageBody,
            ),
            subtitle: Text(
              enabled
                  ? 'Hardline asks for the passphrase each time it starts. '
                        'Without it, the files on this disk are not readable.'
                  : 'Messages, encryption keys, your access token and cached '
                        'attachments are written to this disk in the clear. '
                        'Turning this on locks them behind a passphrase.',
              style: context.text.timestamp,
            ),
            onChanged: status.busy
                ? null
                : (value) => value
                      ? _enable(context, controller)
                      : _disable(context, controller),
          ),

          if (enabled) ...[
            const SettingsDivider(),
            SettingsRow(
              title: 'Passphrase',
              subtitle:
                  'Changing it re-encrypts every account stored here. There is '
                  'no way to recover the old one, and no way to recover this '
                  'one either.',
              trailing: TextButton(
                onPressed: status.busy
                    ? null
                    : () => _change(context, controller),
                child: const Text('Change'),
              ),
            ),
          ],

          if (status.busy) ...[
            const SettingsDivider(),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status.message ?? 'Working…',
                    style: context.text.subtitle,
                  ),
                ),
              ],
            ),
          ],

          if (status.error case final error?) ...[
            const SettingsDivider(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: context.colors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error,
                    style: context.text.subtitle.copyWith(
                      color: context.colors.danger,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: controller.dismissError,
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],

          const SettingsDivider(),
          // The honest limits, in the place somebody is deciding whether to
          // trust it. A padlock that is not explained is read as protecting
          // more than it does, and this one protects a specific and narrow
          // thing: files at rest, read by somebody who is not this user.
          Text(
            'What this covers: another account on this computer, a backup, or '
            'a disk lifted out of the machine. What it does not cover: '
            'anything running as you while Hardline is unlocked — it has the '
            'passphrase in memory, and so would malware wearing your login. '
            'Turning it on also cannot erase what was already written in the '
            'clear; fragments of the old files may stay recoverable until the '
            'disk reuses that space. Full-disk encryption is what covers that, '
            'and is worth having either way.',
            style: context.text.timestamp,
          ),
        ],
      ),
    );
  }

  Future<void> _enable(
    BuildContext context,
    DeviceEncryptionController controller,
  ) async {
    final passphrase = await promptForNewPassphrase(
      context,
      title: 'Choose a passphrase',
      action: 'Encrypt',
      explanation:
          'Hardline will ask for this every time it starts, and it is not '
          'stored anywhere — not on this disk, not on the homeserver. If it is '
          'forgotten, the only way back into the app is to erase what is '
          'stored here and sign in again, which loses the encryption keys for '
          'any history no other device of yours holds.',
    );
    if (passphrase != null) await controller.enable(passphrase);
  }

  Future<void> _change(
    BuildContext context,
    DeviceEncryptionController controller,
  ) async {
    final passphrase = await promptForNewPassphrase(
      context,
      title: 'Change the passphrase',
      action: 'Change',
      explanation:
          'Every account stored on this device is re-encrypted with the new '
          'passphrase. The old one stops working as soon as this finishes.',
    );
    if (passphrase != null) await controller.changePassphrase(passphrase);
  }

  Future<void> _disable(
    BuildContext context,
    DeviceEncryptionController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.colors;
        return AlertDialog(
          backgroundColor: colors.floatingSurface,
          title: Text(
            'Stop encrypting this device?',
            style: dialogContext.text.title,
          ),
          content: SizedBox(
            width: 420,
            child: Text(
              'Your messages, your encryption keys and your access token go '
              'back to being ordinary readable files on this disk. Hardline '
              'will stop asking for a passphrase at startup.',
              style: dialogContext.text.subtitle,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Stop encrypting'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await controller.disable();
  }
}

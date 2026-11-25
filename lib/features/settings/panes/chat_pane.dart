// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/chat_prefs.dart';
import '../../chat/message_drafts.dart';
import '../widgets/settings_layout.dart';

/// How the chat panel behaves, as distinct from what it looks like.
///
/// Appearance owns the colours and the type; this owns the composer.
class ChatPane extends ConsumerWidget {
  const ChatPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(chatPrefsProvider);

    return SettingsPane(
      title: 'Chat',
      description: 'How messages are written, sent and announced.',
      children: [
        const SettingsLabel('Drafts'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SettingsSwitchTile(
            value: prefs.keepDrafts,
            title: 'Keep what I have typed but not sent',
            subtitle:
                'A half-written message stays in the box when you open '
                'settings, join a call, or switch to another channel and come '
                'back. Drafts are held in memory only and do not survive '
                'closing the app.',
            onChanged: (value) async {
              await ref.read(chatPrefsProvider.notifier).setKeepDrafts(value);
              // Forgetting what was already kept, rather than leaving drafts
              // to be restored by a composer that has been told not to save
              // any. Otherwise switching this off appears to do nothing until
              // each room has been visited once more.
              if (!value) ref.read(messageDraftsProvider.notifier).clearAll();
            },
          ),
        ),
        const SettingsLabel('Notifications'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              SettingsSwitchTile(
                key: const Key('settings_notify'),
                value: prefs.notify,
                title: 'Show desktop notifications',
                subtitle:
                    'For the messages your notification settings on the '
                    'server say should notify you: mentions, direct messages '
                    'and rooms you have not muted. Not for the room you are '
                    'reading while Hardline is in front.',
                onChanged: (value) =>
                    ref.read(chatPrefsProvider.notifier).setNotify(value),
              ),
              SettingsSwitchTile(
                key: const Key('settings_notification_preview'),
                value: prefs.notificationPreview,
                title: 'Show message text in notifications',
                subtitle:
                    'Off, a notification says only who wrote and where. '
                    'Notifications are kept in the system\'s history, '
                    'outside Hardline\'s encryption.',
                onChanged: prefs.notify
                    ? (value) => ref
                          .read(chatPrefsProvider.notifier)
                          .setNotificationPreview(value)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

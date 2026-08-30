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
      description: 'How messages are written and sent.',
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
      ],
    );
  }
}

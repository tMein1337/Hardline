// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../security_prefs.dart';
import '../widgets/settings_layout.dart';

/// The safeguards that stand between a stray click and something leaving the
/// app.
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
          'How careful the app is with things that leave it. These apply to '
          'this installation, not to one account.',
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
      ],
    );
  }
}

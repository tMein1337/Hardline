// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../theme/theme_context.dart';
import '../composer_target.dart';
import '../message_content.dart';
import 'reaction_row.dart';
import 'reply_preview.dart';

/// The small bar of actions that appears over a message while it is hovered.
///
/// Drawn by `MessageTile` in its top-right corner. Shown on hover only, so a
/// screen of messages is not a screen of buttons — the same trade every
/// desktop chat client makes.
class MessageActionBar extends ConsumerWidget {
  const MessageActionBar({
    super.key,
    required this.original,
    required this.shown,
  });

  /// The message as first sent: relations point at its id.
  final Event original;

  /// What is on screen — the newest edit, if any. Editing starts from it.
  final Event shown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    // A message the server has not accepted yet has no real id to point at.
    final canRelate = original.status.isSent;

    return Material(
      color: colors.floatingSurface,
      elevation: 2,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.divider),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (context) => MessageActionButton(
                key: const Key('message_action_react'),
                icon: Icons.add_reaction_outlined,
                tooltip: 'Add reaction',
                onPressed: canRelate
                    ? () => pickAndReact(context, ref, original)
                    : null,
              ),
            ),
            MessageActionButton(
              key: const Key('message_action_reply'),
              icon: Icons.reply,
              tooltip: 'Reply',
              onPressed: canRelate
                  ? () => ref
                        .read(composerTargetsProvider.notifier)
                        .replyTo(original)
                  : null,
            ),
            if (isEditableByMe(original))
              MessageActionButton(
                key: const Key('message_action_edit'),
                icon: Icons.edit_outlined,
                tooltip: 'Edit',
                onPressed: () => ref
                    .read(composerTargetsProvider.notifier)
                    .edit(original, text: editableText(shown)),
              ),
          ],
        ),
      ),
    );
  }
}

/// One icon in [MessageActionBar].
class MessageActionButton extends StatelessWidget {
  const MessageActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: 18,
      color: context.colors.textMuted,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 30),
      padding: EdgeInsets.zero,
    );
  }
}

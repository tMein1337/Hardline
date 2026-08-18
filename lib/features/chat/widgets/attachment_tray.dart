// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../attachments/attachment_draft_controller.dart';
import 'attachment_chip.dart';

/// Staged attachments, shown above the composer's input row.
///
/// Lives *inside* the composer's container so the tray and the text field read
/// as one surface. Collapses to nothing when the room
/// has no drafts, which keeps the composer byte-identical to before this
/// feature for a plain text message.
class AttachmentTray extends ConsumerWidget {
  const AttachmentTray({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachments = ref.watch(roomAttachmentsProvider(roomId));
    if (attachments.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.attachmentTray,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 8,
          children: [
            for (final attachment in attachments)
              AttachmentChip(
                key: ValueKey(attachment.id),
                attachment: attachment,
                onRemove: () => ref
                    .read(attachmentDraftsProvider.notifier)
                    .remove(roomId, attachment.id),
              ),
          ],
        ),
      ),
    );
  }
}

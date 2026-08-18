// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/util/byte_format.dart';
import '../../../theme/theme_context.dart';
import '../attachments/attachment_download.dart';
import '../attachments/attachment_errors.dart';
import '../attachments/attachment_kind.dart';
import 'attachment_icons.dart';

/// A non-previewable attachment: an icon, the name, the size and a save button.
class AttachmentCard extends StatefulWidget {
  const AttachmentCard({
    super.key,
    required this.event,
    required this.kind,
    required this.isPending,
  });

  final Event event;
  final AttachmentKind kind;

  /// While true the bytes are still being uploaded, so there is nothing to
  /// download yet.
  final bool isPending;

  @override
  State<AttachmentCard> createState() => _AttachmentCardState();
}

class _AttachmentCardState extends State<AttachmentCard> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await saveAttachment(widget.event);
    } catch (error) {
      debugPrint('Could not save ${widget.event.eventId}: $error');
      if (mounted) setState(() => _error = describeAttachmentError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final event = widget.event;
    final name = event.content.tryGet<String>('filename') ?? event.body;
    final size = event.infoMap.tryGet<int>('size');
    final error = _error;

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.attachmentCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.attachmentCardBorder),
      ),
      child: Row(
        children: [
          Icon(
            iconForAttachment(widget.kind),
            size: 32,
            color: colors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: context.text.messageBody.copyWith(
                    color: colors.textLink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  error ?? (size == null ? '' : formatBytes(size)),
                  style: context.text.timestamp.copyWith(
                    color: error == null ? colors.textMuted : colors.danger,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!widget.isPending)
            IconButton(
              onPressed: _saving ? null : _save,
              iconSize: 20,
              color: error == null ? colors.textMuted : colors.danger,
              tooltip: error ?? 'Save',
              icon: _saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.textMuted,
                      ),
                    )
                  : Icon(
                      error == null
                          ? Icons.download_outlined
                          : Icons.error_outline,
                    ),
            ),
        ],
      ),
    );
  }
}

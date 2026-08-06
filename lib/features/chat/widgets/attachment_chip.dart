import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/util/byte_format.dart';
import '../../../theme/theme_context.dart';
import '../attachments/attachment_kind.dart';
import '../attachments/pending_attachment.dart';
import 'attachment_icons.dart';

/// Edge length of a chip's preview square.
const _previewSize = 56.0;

/// Total chip width. Wide enough for a readable name, narrow enough that four
/// fit across the composer before the tray scrolls.
const _chipWidth = 168.0;

/// One staged attachment in the composer's tray.
///
/// Rejected attachments are drawn here too, in the danger color with the reason
/// underneath, rather than being dropped silently — when five files are dropped
/// at once the user has to see *which* one the server will not take.
class AttachmentChip extends StatelessWidget {
  const AttachmentChip({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  final PendingAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rejection = attachment.rejection;

    return Container(
      width: _chipWidth,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.attachmentChip,
        borderRadius: BorderRadius.circular(8),
        border: rejection == null
            ? null
            : Border.all(color: colors.danger, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Preview(attachment: attachment),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  attachment.name,
                  style: context.text.subtitle.copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  rejection ?? formatBytes(attachment.size),
                  style: context.text.timestamp.copyWith(
                    color: rejection == null ? colors.textMuted : colors.danger,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Sized down from the default 48px tap target: at full size the
          // button is taller than the chip it sits in.
          SizedBox(
            width: 24,
            height: 24,
            child: IconButton(
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              iconSize: 16,
              color: colors.textMuted,
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.attachment});

  final PendingAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final source = attachment.source;

    // Only on-disk images get a thumbnail. A clipboard blob is already in
    // memory so it could be shown too, but Image.memory on every rebuild of a
    // 20 MB paste is not worth the preview.
    if (attachment.kind == AttachmentKind.image && source is OnDiskBytes) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(source.path),
          width: _previewSize,
          height: _previewSize,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _Icon(kind: attachment.kind),
        ),
      );
    }

    return _Icon(kind: attachment.kind);
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.kind});

  final AttachmentKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: _previewSize,
      height: _previewSize,
      decoration: BoxDecoration(
        color: colors.attachmentPlaceholder,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(iconForAttachment(kind), size: 24, color: colors.textMuted),
    );
  }
}

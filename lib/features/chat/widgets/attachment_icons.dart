import 'package:flutter/material.dart';

import '../attachments/attachment_kind.dart';

/// The glyph that stands in for an attachment with no preview.
///
/// Used by the composer's tray chips and by the timeline's cards and failed
/// previews, so the same file type never gets two different icons.
IconData iconForAttachment(AttachmentKind kind) => switch (kind) {
  AttachmentKind.image => Icons.image_outlined,
  AttachmentKind.video => Icons.movie_outlined,
  AttachmentKind.audio => Icons.audiotrack_outlined,
  AttachmentKind.file => Icons.insert_drive_file_outlined,
};

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'attachment_draft_controller.dart';
import 'attachment_intake.dart';
import 'pending_attachment.dart';

/// Bytes that arrived without a path — a pasted screenshot, or a virtual file
/// dragged out of Outlook or a zip viewer.
typedef AttachmentBlob = ({Uint8List bytes, String mimeType, String? name});

/// What a paste or a drop turned up.
///
/// The shape every source adapter returns. Records are structural, so an
/// adapter can build one without importing anything from the others.
typedef IncomingAttachments = ({
  List<String> paths,
  List<AttachmentBlob> blobs,
});

/// Puts everything a paste or a drop produced into a room's tray.
///
/// The single entry point for all three input paths — the attach button, a drop
/// and a paste all end here, so the cap, the size check and the mime sniffing
/// cannot drift apart between them.
///
/// Returns true when something was staged, which is what tells a paste whether
/// to suppress the text it would otherwise have inserted.
Future<bool> stageIncoming(
  WidgetRef ref, {
  required String roomId,
  required IncomingAttachments incoming,
}) async {
  if (incoming.paths.isEmpty && incoming.blobs.isEmpty) return false;

  final intake = await ref.read(attachmentIntakeProvider.future);

  final staged = <PendingAttachment>[
    ...await intake.fromPaths(incoming.paths),
    for (final blob in incoming.blobs)
      if (blob.bytes.isNotEmpty)
        intake.fromBytes(
          bytes: blob.bytes,
          // A blob with no name of its own gets one shaped like a screenshot.
          name: blob.name ?? clipboardImageName(blob.mimeType),
          mimeType: blob.mimeType,
        ),
  ];

  return _stage(ref, roomId, staged);
}

/// Puts picked or dropped file paths into a room's tray.
Future<bool> stagePaths(
  WidgetRef ref, {
  required String roomId,
  required List<String> paths,
}) => stageIncoming(
  ref,
  roomId: roomId,
  incoming: (paths: paths, blobs: const []),
);

bool _stage(WidgetRef ref, String roomId, List<PendingAttachment> staged) {
  if (staged.isEmpty) return false;

  final dropped = ref
      .read(attachmentDraftsProvider.notifier)
      .addAll(roomId, staged);

  if (dropped > 0) {
    debugPrint(
      'Dropped $dropped attachment(s): a message may carry at most '
      '$kMaxAttachmentsPerMessage.',
    );
  }
  return true;
}

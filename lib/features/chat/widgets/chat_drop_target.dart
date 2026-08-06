import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attachments/attachment_drop_source.dart';
import '../attachments/attachment_staging.dart';
import 'attachment_drop_overlay.dart';

/// Accepts files dropped anywhere on the chat area and stages them.
///
/// The hover flag is local [State] rather than a provider: it changes on every
/// drag-over tick, and routing that through Riverpod would rebuild the whole
/// chat panel dozens of times per second for a purely decorative wash.
class ChatDropTarget extends ConsumerStatefulWidget {
  const ChatDropTarget({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.child,
  });

  final String roomId;
  final String roomName;
  final Widget child;

  @override
  ConsumerState<ChatDropTarget> createState() => _ChatDropTargetState();
}

class _ChatDropTargetState extends ConsumerState<ChatDropTarget> {
  bool _dragging = false;

  void _setDragging(bool value) {
    if (_dragging == value || !mounted) return;
    setState(() => _dragging = value);
  }

  Future<void> _onDropped(IncomingAttachments incoming) async {
    if (!mounted) return;
    await stageIncoming(ref, roomId: widget.roomId, incoming: incoming);
  }

  @override
  Widget build(BuildContext context) {
    return AttachmentDropTarget(
      onDragging: _setDragging,
      onDropped: _onDropped,
      // passthrough hands the incoming constraints to the child unchanged, so
      // with nothing being dragged the layout is identical to having no drop
      // target at all.
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              // Never eat the drop: the DropRegion below is the hit target.
              child: IgnorePointer(
                child: AttachmentDropOverlay(roomName: widget.roomName),
              ),
            ),
        ],
      ),
    );
  }
}

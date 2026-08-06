import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../theme/theme_context.dart';
import '../attachments/attachment_draft_controller.dart';
import '../attachments/attachment_picker_source.dart';
import '../attachments/attachment_staging.dart';
import '../attachments/pending_attachment.dart';
import '../timeline_controller.dart';
import '../timeline_provider.dart';
import 'attachment_tray.dart';
import 'paste_attachment_action.dart';

/// The message input.
///
/// Enter sends; Shift+Enter inserts a newline. Attachments staged in the tray
/// above go out with the same keystroke, and the typed text becomes their
/// caption.
class MessageComposer extends ConsumerStatefulWidget {
  const MessageComposer({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  final String roomId;
  final String roomName;

  @override
  ConsumerState<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<MessageComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  /// Held here rather than built inline: a fresh instance on every rebuild
  /// would reset the action's own re-entrancy guard, so a second Ctrl+V while
  /// the first clipboard read is still in flight would stage the image twice.
  late final _pasteAction = PasteAttachmentAction(
    onAttachments: _stageFromClipboard,
  );

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;

    final text = _controller.text;
    final attachments = ref.read(roomAttachmentsProvider(widget.roomId));

    if (text.trim().isEmpty && attachments.isEmpty) return;
    // Enter must not silently discard the file the server would refuse.
    if (attachments.any((attachment) => !attachment.isValid)) return;

    // Cleared first so the field feels instant; the local echo appears in the
    // timeline before the request completes anyway.
    _controller.clear();
    setState(() => _sending = true);
    try {
      final controller = ref.read(timelineControllerProvider(widget.roomId));

      if (attachments.isEmpty) {
        await controller.send(text);
      } else {
        await _sendAttachments(controller, attachments, text);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
      _focus.requestFocus();
    }
  }

  Future<void> _sendAttachments(
    TimelineController controller,
    List<PendingAttachment> attachments,
    String caption,
  ) async {
    // Reading the bytes can fail if a staged file was moved or deleted while it
    // sat in the tray. Those are skipped rather than aborting the whole batch.
    final files = <MatrixFile>[];
    for (final attachment in attachments) {
      try {
        files.add(await attachment.toMatrixFile(controller.client));
      } catch (error) {
        debugPrint('Could not read ${attachment.name}: $error');
      }
    }

    // Cleared before the upload, not after: sendFileEvent already shows a
    // pending tile in the timeline, so leaving the chips up would show the same
    // files twice for the length of the upload.
    ref.read(attachmentDraftsProvider.notifier).clear(widget.roomId);

    // Deliberately not awaited. sendFileEvent resolves only once the bytes are
    // on the server, and blocking the composer on that would lock the input for
    // a minute on a large video. The local echo is already in the timeline with
    // its own progress and error states, so there is nothing left here to wait
    // for. sendFiles owns its errors; the controller outliving a room switch is
    // fine because the upload runs against the SDK's Room, not this object.
    unawaited(controller.sendFiles(files, caption: caption));
  }

  Future<void> _pickFiles() async {
    final paths = await pickAttachmentPaths();
    if (!mounted) return;
    await stagePaths(ref, roomId: widget.roomId, paths: paths);
  }

  /// Stages whatever a paste turned up. Returns false to let the normal text
  /// paste proceed untouched.
  Future<bool> _stageFromClipboard(IncomingAttachments found) async {
    if (!mounted) return false;
    return stageIncoming(ref, roomId: widget.roomId, incoming: found);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored; // let the newline through
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;
    final attachments = ref.watch(roomAttachmentsProvider(widget.roomId));
    final blocked = attachments.any((attachment) => !attachment.isValid);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.contentPadding,
        0,
        metrics.contentPadding,
        24,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.inputBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AttachmentTray(roomId: widget.roomId),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  // Actions sits outside the Focus so it is an ancestor of the
                  // TextField — that is what EditableText's overridable paste
                  // action looks up — while still being a descendant of the
                  // root DefaultTextEditingActions it delegates back to.
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      PasteTextIntent: _pasteAction,
                    },
                    child: Focus(
                      onKeyEvent: _onKey,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        style: context.text.inputText,
                        maxLines: 8,
                        minLines: 1,
                        cursorColor: colors.textHeader,
                        decoration: InputDecoration(
                          hintText: attachments.isEmpty
                              ? 'Message #${widget.roomName}'
                              : 'Add a caption',
                          hintStyle: context.text.inputText.copyWith(
                            color: colors.textFaint,
                          ),
                          // The container already provides the surface and
                          // padding.
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _pickFiles,
                  iconSize: 20,
                  color: colors.textMuted,
                  tooltip: 'Attach a file',
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  onPressed: _sending || blocked ? null : _send,
                  iconSize: 20,
                  color: colors.textMuted,
                  tooltip: blocked
                      ? 'Remove the files this server will not accept'
                      : 'Send',
                  icon: _sending
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textMuted,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

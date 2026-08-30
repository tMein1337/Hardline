// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../theme/color_slots.dart';
import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../attachments/attachment_draft_controller.dart';
import '../attachments/attachment_picker_source.dart';
import '../attachments/attachment_staging.dart';
import '../attachments/pending_attachment.dart';
import '../chat_prefs.dart';
import '../mention_candidates_provider.dart';
import '../mentions.dart';
import '../message_drafts.dart';
import '../timeline_controller.dart';
import '../typing_notifier.dart';
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

  TypingNotifier? _typing;

  /// The `@…` being completed, and where it starts in the text.
  ///
  /// Null whenever the popup is closed, which is most of the time.
  ({String query, int start})? _mention;

  /// Which suggestion the arrow keys are on.
  int _mentionIndex = 0;

  @override
  void initState() {
    super.initState();

    final room = ref.read(clientProvider).getRoomById(widget.roomId);
    if (room != null) _typing = TypingNotifier(room);

    // Withdrawn on blur as well as on send: leaving the box to read something
    // else is not typing, and the badge would otherwise stand until the
    // server's own timeout.
    _focus.addListener(() {
      if (!_focus.hasFocus) unawaited(_typing?.stop());
    });
    // Restores what was typed here before. `ChatPanel` gives this widget a
    // `ValueKey(roomId)`, so `initState` runs once per room rather than the
    // `State` being reused across them — which is what used to carry one
    // room's draft into the next.
    final draft = ref.read(roomDraftProvider(widget.roomId));
    if (draft.isNotEmpty) {
      _controller.text = draft;
      _controller.selection = TextSelection.collapsed(offset: draft.length);
    }
  }

  /// Held here rather than built inline: a fresh instance on every rebuild
  /// would reset the action's own re-entrancy guard, so a second Ctrl+V while
  /// the first clipboard read is still in flight would stage the image twice.
  late final _pasteAction = PasteAttachmentAction(
    onAttachments: _stageFromClipboard,
  );

  @override
  void dispose() {
    unawaited(_typing?.dispose());
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Records the draft, so it survives this widget being taken down.
  ///
  /// Which happens far more often than it looks: joining a call swaps the
  /// conversation out for the grid, and a settings action that invalidates the
  /// account-sync provider rebuilds the whole shell. Neither is navigation the
  /// user would describe as leaving the room.
  void _onChanged(String text) {
    _typing?.onChanged(text);
    _refreshMention();
    if (!ref.read(chatPrefsProvider).keepDrafts) return;
    ref.read(messageDraftsProvider.notifier).set(widget.roomId, text);
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
    ref.read(messageDraftsProvider.notifier).clear(widget.roomId);
    // Before the send rather than after: the message arriving is itself proof
    // the typing stopped, and waiting for the round trip leaves the badge up
    // alongside the message it announced.
    unawaited(_typing?.stop());
    setState(() => _sending = true);
    try {
      final controller = ref.read(timelineControllerProvider(widget.roomId));

      if (attachments.isEmpty) {
        await controller.send(
          text,
          candidates: ref.read(mentionCandidatesProvider(widget.roomId)),
        );
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

  /// Recomputes the completion from the caret, and closes it when there is no
  /// `@` run under it.
  void _refreshMention() {
    final selection = _controller.selection;
    // A range selection is not a caret, and completing into one would replace
    // text somebody had deliberately highlighted.
    final query = selection.isCollapsed
        ? mentionQuery(_controller.text, selection.baseOffset)
        : null;

    if (query == _mention) return;
    setState(() {
      _mention = query;
      _mentionIndex = 0;
    });
  }

  List<MentionCandidate> get _suggestions {
    final mention = _mention;
    if (mention == null) return const [];
    return rankMentions(
      ref.read(mentionCandidatesProvider(widget.roomId)),
      mention.query,
    );
  }

  void _accept(MentionCandidate candidate) {
    final mention = _mention;
    if (mention == null) return;

    final result = applyMention(
      text: _controller.text,
      start: mention.start,
      cursor: _controller.selection.baseOffset,
      candidate: candidate,
    );

    _controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.cursor),
    );
    setState(() => _mention = null);
    _onChanged(result.text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // The completion owns these keys while it is open, and only then — Enter
    // must still send when it is closed, and Escape must still do nothing.
    final suggestions = _mention == null
        ? const <MentionCandidate>[]
        : _suggestions;
    if (suggestions.isNotEmpty) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.tab:
        case LogicalKeyboardKey.enter:
          _accept(suggestions[_mentionIndex.clamp(0, suggestions.length - 1)]);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowDown:
          setState(
            () => _mentionIndex = (_mentionIndex + 1) % suggestions.length,
          );
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          setState(
            () => _mentionIndex =
                (_mentionIndex - 1 + suggestions.length) % suggestions.length,
          );
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          setState(() => _mention = null);
          return KeyEventResult.handled;
      }
    }

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

    final suggestions = _mention == null
        ? const <MentionCandidate>[]
        : _suggestions;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.contentPadding,
        0,
        metrics.contentPadding,
        24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Above the box rather than floating over the timeline: an overlay
          // would need a `CompositedTransformFollower` and would still be
          // wrong the moment the composer grew to two lines. This just pushes
          // the input down, which is what every other client does.
          if (suggestions.isNotEmpty)
            _MentionList(
              suggestions: suggestions,
              selected: _mentionIndex.clamp(0, suggestions.length - 1),
              onPick: _accept,
            ),
          _inputBox(context, colors, attachments, blocked),
        ],
      ),
    );
  }

  Widget _inputBox(
    BuildContext context,
    AppPalette colors,
    List<PendingAttachment> attachments,
    bool blocked,
  ) {
    return Container(
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
                      onChanged: _onChanged,
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
    );
  }
}

/// The `@` completion, drawn above the composer.
///
/// Keyboard-first: the arrow keys move the highlight and Tab or Enter accepts,
/// which is what people type without being told. Clicking works too, for the
/// people who look.
class _MentionList extends StatelessWidget {
  const _MentionList({
    required this.suggestions,
    required this.selected,
    required this.onPick,
  });

  final List<MentionCandidate> suggestions;
  final int selected;
  final ValueChanged<MentionCandidate> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colors.floatingSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, candidate) in suggestions.indexed)
            Hoverable(
              onTap: () => onPick(candidate),
              builder: (context, hovered) => Container(
                color: index == selected
                    ? colors.listItemSelected
                    : hovered
                    ? colors.listItemHover
                    : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Row(
                  children: [
                    MxAvatar(
                      name: candidate.displayName,
                      seed: candidate.userId,
                      mxcUri: candidate.avatarMxc,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        candidate.displayName,
                        style: context.text.messageBody,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // The id as well as the name, for the same reason the
                    // profile dialog shows it: two people can share a display
                    // name, and picking the wrong one is silent.
                    Flexible(
                      child: Text(
                        candidate.userId,
                        style: context.text.timestamp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

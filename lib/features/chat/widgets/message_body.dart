import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../theme/theme_context.dart';
import '../attachments/attachment_errors.dart';
import '../attachments/attachment_kind.dart';
import 'attachment_card.dart';
import 'attachment_image.dart';

const _localizations = MatrixDefaultLocalizations();

/// The content of one message row, below the sender line.
///
/// Branches on [AttachmentKind] rather than adding a variant to `TimelineItem`.
/// The sealed variants there encode *row shape* — avatar, gutter, hover, the
/// mention bar — and an attachment message is still an ordinary message in all
/// of those respects. It also has to keep grouping with the sender's text
/// messages, which `message_grouping.dart` does by event type alone; a new
/// variant would invite someone to "fix" that and silently break it.
///
/// The exhaustiveness guarantee is relocated, not abandoned: the switch below
/// covers every [AttachmentKind], and `attachmentKindOf` is unit-tested.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.event,
    required this.isPending,
  });

  final Event event;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final kind = attachmentKindOf(event);
    if (kind == null) return _Text(event: event, isPending: isPending);

    final caption = attachmentCaption(event.content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (event.status.isError)
          _FailedUpload(event: event)
        else
          switch (kind) {
            AttachmentKind.image ||
            AttachmentKind.video => AttachmentImage(
              event: event,
              kind: kind,
              isPending: isPending,
            ),
            AttachmentKind.audio || AttachmentKind.file => AttachmentCard(
              event: event,
              kind: kind,
              isPending: isPending,
            ),
          },
        if (isPending && !event.status.isError) _UploadProgress(event: event),
        if (caption != null) ...[
          const SizedBox(height: 4),
          SelectableText(caption, style: context.text.messageBody),
        ],
      ],
    );
  }
}

class _Text extends StatelessWidget {
  const _Text({required this.event, required this.isPending});

  final Event event;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    // Resolves replies, edits and non-text message types to something
    // presentable, and handles pending sends.
    final body = event.calcLocalizedBodyFallback(
      _localizations,
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
    );

    return SelectableText(
      body,
      style: context.text.messageBody.copyWith(
        color: isPending
            ? context.colors.textMuted
            : context.text.messageBody.color,
      ),
    );
  }
}

/// What stage a still-uploading attachment is at.
///
/// Indeterminate on purpose: `FileSendingStatus` is a three-value enum and the
/// SDK exposes no byte counter, so a percentage would be invented.
class _UploadProgress extends StatelessWidget {
  const _UploadProgress({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final label = switch (event.fileSendingStatus) {
      FileSendingStatus.generatingThumbnail => 'Preparing…',
      FileSendingStatus.encrypting => 'Encrypting…',
      FileSendingStatus.uploading => 'Uploading…',
      null => 'Sending…',
    };

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: context.text.timestamp.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: colors.attachmentPlaceholder,
              color: colors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// A failed upload, with the two things worth offering: try again, or drop it.
class _FailedUpload extends StatefulWidget {
  const _FailedUpload({required this.event});

  final Event event;

  @override
  State<_FailedUpload> createState() => _FailedUploadState();
}

class _FailedUploadState extends State<_FailedUpload> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Reads the bytes back out of the SDK's cache and re-enters
      // sendFileEvent. Throws FileNoLongerInCacheException once the cache has
      // expired, which is a different message and leaves only Remove.
      await widget.event.sendAgain();
    } catch (error) {
      debugPrint('Could not retry ${widget.event.eventId}: $error');
      if (mounted) setState(() => _error = describeAttachmentError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    try {
      await widget.event.cancelSend();
    } catch (error) {
      debugPrint('Could not remove ${widget.event.eventId}: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name =
        widget.event.content.tryGet<String>('filename') ?? widget.event.body;
    final error = _error;

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.attachmentCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.danger),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: colors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  error ?? 'Could not upload $name',
                  style: context.text.subtitle.copyWith(color: colors.danger),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // A file that is no longer cached can never be retried, so the
              // button would be a lie.
              if (error == null)
                TextButton(
                  onPressed: _busy ? null : _retry,
                  child: const Text('Retry'),
                ),
              TextButton(
                onPressed: _busy ? null : _remove,
                child: Text(
                  'Remove',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

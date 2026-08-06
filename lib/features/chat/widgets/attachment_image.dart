import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/avatar_uri_provider.dart';
import '../../../theme/theme_context.dart';
import '../attachments/attachment_kind.dart';
import 'attachment_icons.dart';

/// Discord's inline preview ceiling.
const _maxWidth = 400.0;
const _maxHeight = 350.0;

/// Fallback box when the event carries no dimensions — 16:9 at the max width.
const _fallbackWidth = _maxWidth;
const _fallbackHeight = 225.0;

/// Above this an encrypted image with no thumbnail is not worth pulling in full
/// just for a preview. Matches the SDK file cache ceiling in
/// `matrix_bootstrap.dart`.
const _maxInlineDecryptBytes = 10 * 1024 * 1024;

/// An inline image or video preview in the timeline.
///
/// The box is sized from `info.w`/`info.h` *before* the bytes are resolved, so
/// the row never jumps when the image lands. Our own sends carry those
/// dimensions too, because `PendingAttachment.toMatrixFile` runs
/// `MatrixImageFile.create` before handing the file to the SDK.
class AttachmentImage extends ConsumerStatefulWidget {
  const AttachmentImage({
    super.key,
    required this.event,
    required this.kind,
    required this.isPending,
  });

  final Event event;
  final AttachmentKind kind;
  final bool isPending;

  @override
  ConsumerState<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends ConsumerState<AttachmentImage> {
  /// Resolved once per tile rather than through a provider family.
  ///
  /// `message_item.dart` is explicit that timeline events are SDK-mutated and
  /// deliberately kept out of provider state; keying a family on one would
  /// contradict that directly. `MessageList` already keys tiles by event id, so
  /// this State survives rebuilds and the SDK's own file cache absorbs repeats
  /// across scrolls.
  Future<ImageProvider?>? _image;

  @override
  void initState() {
    super.initState();
    _image = _resolve();
  }

  @override
  void didUpdateWidget(AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A pending upload has no bytes on the server yet. When it lands, the event
    // gains a url and this has to be resolved again.
    if (oldWidget.isPending && !widget.isPending) {
      setState(() => _image = _resolve());
    }
  }

  Future<ImageProvider?> _resolve() async {
    final event = widget.event;
    if (!event.hasAttachment) return null;

    try {
      final uri = await event.getAttachmentUri(getThumbnail: true);

      // Unencrypted: an authenticated URL, the same shape mx_avatar.dart uses.
      if (uri != null) {
        if (!mounted) return null;
        return NetworkImage(
          uri.toString(),
          headers: ref.read(mediaRequestHeaders),
        );
      }

      // Encrypted: getAttachmentUri returns null because the bytes on the
      // server are ciphertext and Image.network cannot do anything with them.
      // The SDK downloads, decrypts and caches instead.
      if (!_canDecryptInline(event)) return null;

      final file = await event.downloadAndDecryptAttachment(
        // Passing true without a thumbnail present throws rather than falling
        // back, so the presence check has to happen here.
        getThumbnail: event.hasThumbnail,
      );
      return MemoryImage(file.bytes);
    } catch (error) {
      debugPrint('Could not load the attachment ${event.eventId}: $error');
      return null;
    }
  }

  bool _canDecryptInline(Event event) {
    if (event.hasThumbnail) return true;
    final size = event.infoMap.tryGet<int>('size');
    return size == null || size <= _maxInlineDecryptBytes;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = _boxFor(widget.event);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: colors.attachmentPlaceholder),
            FutureBuilder<ImageProvider?>(
              future: _image,
              builder: (context, snapshot) {
                final image = snapshot.data;
                if (image == null) {
                  return Icon(
                    iconForAttachment(widget.kind),
                    color: colors.textMuted,
                    size: 32,
                  );
                }
                return Image(
                  image: image,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Icon(
                    iconForAttachment(widget.kind),
                    color: colors.textMuted,
                    size: 32,
                  ),
                );
              },
            ),
            // No inline playback in this version: that would mean a video
            // player dependency. The glyph marks it as a video and the card's
            // save button is how you get at it.
            if (widget.kind == AttachmentKind.video)
              Center(
                child: Icon(
                  Icons.play_circle_outline,
                  size: 48,
                  color: colors.textOnAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reserves the final box from the event's own dimensions.
Size _boxFor(Event event) {
  final info = event.infoMap;
  final width = info.tryGet<int>('w');
  final height = info.tryGet<int>('h');

  if (width == null || height == null || width <= 0 || height <= 0) {
    return const Size(_fallbackWidth, _fallbackHeight);
  }

  final scaled = math.min(width.toDouble(), _maxWidth);
  final ratio = height / width;
  return Size(scaled, math.min(scaled * ratio, _maxHeight));
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/avatar_uri_provider.dart';
import '../../../theme/theme_context.dart';
import '../attachments/attachment_download.dart';

/// One image, full size, over the app.
///
/// The timeline draws a thumbnail capped at 400×350 — small enough that a
/// screenshot of anything is unreadable in it, which is the complaint. This
/// loads the **full** attachment rather than the thumbnail the tile uses, and
/// is the first place images and videos can be saved from: `saveAttachment`
/// already existed but only `AttachmentCard` called it, and that handles audio
/// and files alone.
///
/// A route rather than a dialog: it fills the window, takes the keyboard for
/// Escape, and should appear in the back stack like any other full screen.
class ImageViewer extends ConsumerStatefulWidget {
  const ImageViewer({super.key, required this.event});

  final Event event;

  static Future<void> open(BuildContext context, Event event) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (_, _, _) => ImageViewer(event: event),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  ConsumerState<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends ConsumerState<ImageViewer> {
  /// Above this, an encrypted attachment is not decrypted into memory.
  ///
  /// The same ceiling `AttachmentImage` applies inline. Decrypting happens on
  /// the UI isolate, so a very large file would freeze the window for as long
  /// as it took — and the save path below does not need the bytes in memory
  /// at all.
  static const _maxDecryptBytes = 60 * 1024 * 1024;

  late final Future<ImageProvider?> _image = _resolve();
  bool _saving = false;

  Future<ImageProvider?> _resolve() async {
    final event = widget.event;
    if (!event.hasAttachment) return null;

    try {
      // getThumbnail: false — the whole point of this screen.
      final uri = await event.getAttachmentUri(getThumbnail: false);
      if (uri != null) {
        if (!mounted) return null;
        return NetworkImage(
          uri.toString(),
          headers: ref.read(mediaRequestHeaders),
        );
      }

      final size = event.infoMap.tryGet<int>('size');
      if (size != null && size > _maxDecryptBytes) return null;

      final file = await event.downloadAndDecryptAttachment();
      return MemoryImage(file.bytes);
    } catch (error) {
      debugPrint('Could not load ${widget.event.eventId} full size: $error');
      return null;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final saved = await saveAttachment(widget.event);
      if (saved) messenger?.showSnackBar(const SnackBar(content: Text('Saved.')));
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Clicking the backdrop closes, which is what people try before
              // they look for the button.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 64, 48, 48),
                  child: FutureBuilder<ImageProvider?>(
                    future: _image,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final image = snapshot.data;
                      if (image == null) {
                        return Center(
                          child: Text(
                            'Could not load this image at full size. It can '
                            'still be saved.',
                            style: context.text.messageBody,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return InteractiveViewer(
                        maxScale: 8,
                        child: Center(
                          child: Image(image: image, fit: BoxFit.contain),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Save',
                      onPressed: _saving ? null : _save,
                      icon: Icon(
                        Icons.download_outlined,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.close, color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

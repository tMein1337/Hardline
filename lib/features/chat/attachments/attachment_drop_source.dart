/// The `super_drag_and_drop` adapter.
///
/// One of three source files that import an input package. It exposes a widget
/// and a plain-Dart callback; nothing else in the feature knows which package
/// delivers the drop.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'attachment_staging.dart';

/// Wraps [child] in a region that accepts dropped files.
///
/// [onDragging] reports whether something acceptable is currently hovering, so
/// the caller can draw an overlay. [onDropped] fires once with everything the
/// drop contained.
class AttachmentDropTarget extends StatelessWidget {
  const AttachmentDropTarget({
    super.key,
    required this.child,
    required this.onDragging,
    required this.onDropped,
  });

  final Widget child;
  final ValueChanged<bool> onDragging;
  final ValueChanged<IncomingAttachments> onDropped;

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      // fileUri covers ordinary files; the image formats catch a picture
      // dragged straight out of a browser, which arrives as bytes rather than
      // as a file on disk.
      formats: const [
        Formats.fileUri,
        Formats.png,
        Formats.jpeg,
        Formats.gif,
        Formats.webp,
      ],
      // Without an explicit non-none operation Windows shows the no-drop
      // cursor and onPerformDrop never fires at all.
      onDropOver: (_) => DropOperation.copy,
      // The default defers to the child, which would leave gaps wherever the
      // message list happens not to paint.
      hitTestBehavior: HitTestBehavior.opaque,
      onDropEnter: (_) => onDragging(true),
      onDropLeave: (_) => onDragging(false),
      onDropEnded: (_) => onDragging(false),
      onPerformDrop: (event) async {
        onDragging(false);
        final incoming = await _read(event.session.items);
        if (incoming.paths.isNotEmpty || incoming.blobs.isNotEmpty) {
          onDropped(incoming);
        }
      },
      child: child,
    );
  }
}

Future<IncomingAttachments> _read(List<DropItem> items) async {
  final paths = <String>[];
  final blobs = <AttachmentBlob>[];

  for (final item in items) {
    final reader = item.dataReader;
    if (reader == null) continue;

    // Files before images: a PNG dragged from Explorer offers both, and the
    // path keeps the user's original filename and bytes.
    if (reader.canProvide(Formats.fileUri)) {
      final path = await _readPath(reader);
      if (path != null) {
        paths.add(path);
        continue;
      }
    }

    final blob = await _readBlob(reader);
    if (blob != null) blobs.add(blob);
  }

  return (paths: paths, blobs: blobs);
}

Future<String?> _readPath(DataReader reader) async {
  final completer = Completer<Uri?>();

  final progress = reader.getValue(
    Formats.fileUri,
    completer.complete,
    onError: (error) {
      debugPrint('Could not read a dropped file path: $error');
      completer.complete(null);
    },
  );
  if (progress == null) return null;

  final uri = await completer.future;
  if (uri == null || !uri.isScheme('file')) return null;

  try {
    return uri.toFilePath(
      windows: defaultTargetPlatform == TargetPlatform.windows,
    );
  } catch (error) {
    debugPrint('Ignoring a dropped entry that is not a usable path: $error');
    return null;
  }
}

/// Reads a dropped item that has no path.
///
/// This is the case super_drag_and_drop is here for: an attachment dragged
/// straight out of Outlook or a zip viewer is a *virtual* file with no
/// on-disk location, and getFile streams it out for us.
Future<AttachmentBlob?> _readBlob(DataReader reader) async {
  const candidates = <(SimpleFileFormat, String)>[
    (Formats.png, 'image/png'),
    (Formats.jpeg, 'image/jpeg'),
    (Formats.gif, 'image/gif'),
    (Formats.webp, 'image/webp'),
  ];

  for (final (format, mimeType) in candidates) {
    if (!reader.canProvide(format)) continue;

    final completer = Completer<AttachmentBlob?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          completer.complete((
            bytes: await file.readAll(),
            mimeType: mimeType,
            name: file.fileName,
          ));
        } catch (error) {
          debugPrint('Could not read a dropped file: $error');
          completer.complete(null);
        }
      },
      onError: (error) {
        debugPrint('Could not read a dropped file: $error');
        completer.complete(null);
      },
    );
    if (progress == null) continue;

    final blob = await completer.future;
    if (blob != null && blob.bytes.isNotEmpty) return blob;
  }

  return null;
}

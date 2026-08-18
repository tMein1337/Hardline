// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The `super_clipboard` adapter.
///
/// One of three source files that import an input package. Everything it
/// returns is plain Dart — paths and byte blobs — so replacing `super_clipboard`
/// with another reader means rewriting this file and nothing else.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'attachment_staging.dart';

/// Image formats worth accepting, most preferred first.
///
/// PNG leads because Windows synthesises it from the DIB that screenshot tools
/// put on the clipboard, so it is what a Win+Shift+S actually yields.
const _imageFormats = <(SimpleFileFormat, String)>[
  (Formats.png, 'image/png'),
  (Formats.jpeg, 'image/jpeg'),
  (Formats.gif, 'image/gif'),
  (Formats.webp, 'image/webp'),
  (Formats.bmp, 'image/bmp'),
  (Formats.tiff, 'image/tiff'),
];

/// Reads anything attachable from the clipboard.
///
/// Returns null when the clipboard holds nothing we can attach, which is the
/// caller's signal to let the normal text paste proceed.
Future<IncomingAttachments?> readClipboardAttachments() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;

  final reader = await clipboard.read();

  final paths = <String>[];
  final blobs = <AttachmentBlob>[];

  for (final item in reader.items) {
    // Files before images, deliberately. Copying a PNG in Explorer puts both a
    // file reference *and* a bitmap on the clipboard — super_clipboard even
    // synthesises the image format from the file URI. Taking the file keeps the
    // real filename and avoids a lossy re-encode of the user's original.
    if (item.canProvide(Formats.fileUri)) {
      final uri = await item.readValue(Formats.fileUri);
      final path = _toFilePath(uri);
      if (path != null) {
        paths.add(path);
        continue;
      }
    }

    final blob = await _readImage(item);
    if (blob != null) blobs.add(blob);
  }

  if (paths.isEmpty && blobs.isEmpty) return null;
  return (paths: paths, blobs: blobs);
}

Future<AttachmentBlob?> _readImage(ClipboardDataReader item) async {
  for (final (format, mimeType) in _imageFormats) {
    if (!item.canProvide(format)) continue;

    final bytes = await _readFile(item, format);
    if (bytes != null && bytes.isNotEmpty) {
      // A clipboard bitmap carries no name; the staging layer synthesises one.
      return (bytes: bytes, mimeType: mimeType, name: null);
    }
  }
  return null;
}

/// Bridges [DataReader.getFile]'s callback shape to a future.
///
/// getFile is callback-based on purpose — the same reader is used during a drag
/// where awaiting would block platform code — but a clipboard paste has no such
/// constraint.
Future<Uint8List?> _readFile(ClipboardDataReader item, FileFormat format) {
  final completer = Completer<Uint8List?>();

  final progress = item.getFile(
    format,
    (file) async {
      try {
        completer.complete(await file.readAll());
      } catch (error) {
        debugPrint('Could not read the pasted image: $error');
        completer.complete(null);
      }
    },
    onError: (error) {
      debugPrint('Could not read the pasted image: $error');
      completer.complete(null);
    },
  );

  // A null progress means the format turned out not to be readable after all,
  // and neither callback will ever fire.
  if (progress == null) return Future.value(null);

  return completer.future;
}

String? _toFilePath(Uri? uri) {
  if (uri == null || !uri.isScheme('file')) return null;
  try {
    return uri.toFilePath(windows: defaultTargetPlatform == TargetPlatform.windows);
  } catch (error) {
    debugPrint('Ignoring a clipboard entry that is not a usable path: $error');
    return null;
  }
}

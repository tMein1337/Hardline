import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../core/util/byte_format.dart';
import 'attachment_kind.dart';
import 'attachment_limits.dart';
import 'pending_attachment.dart';

const _fallbackMimeType = 'application/octet-stream';

/// Turns raw input from the three sources into staged attachments.
///
/// **The only place [PendingAttachment] is constructed.** Drag-and-drop, the
/// file dialog and the clipboard all funnel through here, so validation, mime
/// sniffing and naming happen once rather than three times with three sets of
/// bugs. The package adapters (`attachment_*_source.dart`) deliberately hand
/// this class plain paths and bytes, which is what keeps them swappable.
@immutable
class AttachmentIntake {
  const AttachmentIntake({this.maxUploadSize});

  /// The homeserver's `m.upload.size`, or null when it advertises none.
  final int? maxUploadSize;

  /// Stages files the user dropped or picked.
  ///
  /// Directories and unreadable entries are skipped rather than rejected —
  /// dropping a folder is a miss, not something worth an error chip.
  Future<List<PendingAttachment>> fromPaths(Iterable<String> paths) async {
    final staged = <PendingAttachment>[];

    for (final path in paths) {
      try {
        if (FileSystemEntity.isDirectorySync(path)) {
          debugPrint('Skipping the dropped directory $path');
          continue;
        }

        final file = File(path);
        final size = await file.length();
        if (size == 0) {
          debugPrint('Skipping the empty file $path');
          continue;
        }

        final name = p.basename(path);
        staged.add(
          _stage(
            name: name,
            mimeType: lookupMimeType(path) ?? _fallbackMimeType,
            size: size,
            source: OnDiskBytes(path),
          ),
        );
      } on FileSystemException catch (error) {
        // A file that vanished between the drop and this read is not worth
        // failing the whole batch over.
        debugPrint('Could not stage $path: $error');
      }
    }

    return staged;
  }

  /// Stages a clipboard blob, which has no path to name it from.
  PendingAttachment fromBytes({
    required Uint8List bytes,
    required String name,
    String? mimeType,
  }) {
    final resolved =
        mimeType ?? lookupMimeType(name, headerBytes: bytes) ?? _fallbackMimeType;

    return _stage(
      name: name,
      mimeType: resolved,
      size: bytes.length,
      source: InMemoryBytes(bytes),
    );
  }

  PendingAttachment _stage({
    required String name,
    required String mimeType,
    required int size,
    required AttachmentBytes source,
  }) {
    final limit = maxUploadSize;

    return PendingAttachment(
      id: _nextId(),
      name: name,
      mimeType: mimeType,
      size: size,
      kind: attachmentKindForMimeType(mimeType),
      source: source,
      rejection: limit != null && size > limit
          ? 'Too large — ${formatBytes(size)}, limit ${formatBytes(limit)}'
          : null,
    );
  }
}

/// A name for a clipboard image, which arrives without one.
///
/// Shaped like Windows' own screenshot naming so a pasted screenshot is
/// recognisable in the room later. The extension comes from the mime type
/// because that is the only thing known about a raw blob.
String clipboardImageName(String mimeType, {DateTime? now}) {
  final at = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');

  final stamp =
      '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}-${two(at.minute)}-${two(at.second)}';

  return 'Screenshot $stamp.${extensionFromMime(mimeType) ?? 'bin'}';
}

var _idCounter = 0;

/// Unique within a session, which is all a tray key and a removal handle need.
String _nextId() => 'attachment-${_idCounter++}';

/// [AttachmentIntake] wired to the server's current upload limit.
final attachmentIntakeProvider = FutureProvider<AttachmentIntake>((ref) async {
  return AttachmentIntake(maxUploadSize: await ref.watch(maxUploadSizeProvider.future));
});

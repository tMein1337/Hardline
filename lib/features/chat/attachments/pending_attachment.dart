// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'attachment_kind.dart';

/// Where a staged attachment's bytes live until it is sent.
///
/// The split is the memory rule, made unforgettable by the type system: drops
/// and the file dialog stage a *path*, so a 200 MB video waiting in the tray
/// costs a `String`. Only clipboard blobs hold bytes, because a screenshot has
/// no path to point at.
sealed class AttachmentBytes {
  const AttachmentBytes();

  /// Reads the bytes. Called once, at send time.
  Future<Uint8List> read();
}

/// A file the user picked or dropped. Read lazily.
final class OnDiskBytes extends AttachmentBytes {
  const OnDiskBytes(this.path);

  final String path;

  @override
  Future<Uint8List> read() => File(path).readAsBytes();
}

/// A clipboard blob, which never had a path.
final class InMemoryBytes extends AttachmentBytes {
  const InMemoryBytes(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> read() async => bytes;
}

/// One attachment staged in the composer's tray, not yet sent.
@immutable
class PendingAttachment {
  const PendingAttachment({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.size,
    required this.kind,
    required this.source,
    this.rejection,
  });

  /// Stable identity for list keys and for removal from the tray.
  final String id;

  /// The file name as it will be sent, and as the tray shows it.
  final String name;

  final String mimeType;

  /// Bytes on disk, or the blob length. Known at staging time so the tray can
  /// show a size and reject oversized files before anything is read.
  final int size;

  final AttachmentKind kind;

  final AttachmentBytes source;

  /// Why this attachment cannot be sent, or null if it is fine.
  ///
  /// Rejected attachments stay in the tray rather than being dropped silently:
  /// a file that vanishes on drop looks like a bug, and the user needs to see
  /// *which* of five files was too big. Send stays disabled while any of these
  /// is present — see `message_composer.dart`.
  final String? rejection;

  bool get isValid => rejection == null;

  /// Converts to the SDK's file type, reading the bytes in the process.
  ///
  /// The one place this feature touches the SDK's file model.
  Future<MatrixFile> toMatrixFile(Client client) async {
    final bytes = await source.read();

    if (kind == AttachmentKind.image) {
      // create() computes width, height and blurhash. Passing
      // nativeImplementations moves that onto the SDK's isolate — without it a
      // 12 MP photo blocks the UI thread for a visible beat.
      //
      // It matters for rendering too: sendFileEvent copies file.info into the
      // local echo verbatim, so computing w/h here is what lets the pending
      // tile reserve the right box and never jump when the image lands.
      return MatrixImageFile.create(
        bytes: bytes,
        name: name,
        mimeType: mimeType,
        nativeImplementations: client.nativeImplementations,
      );
    }

    // Picks MatrixVideoFile / MatrixAudioFile / MatrixFile by mime type.
    return MatrixFile.fromMimeType(
      bytes: bytes,
      name: name,
      mimeType: mimeType,
    );
  }

  PendingAttachment copyWith({String? rejection}) => PendingAttachment(
    id: id,
    name: name,
    mimeType: mimeType,
    size: size,
    kind: kind,
    source: source,
    rejection: rejection ?? this.rejection,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PendingAttachment && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

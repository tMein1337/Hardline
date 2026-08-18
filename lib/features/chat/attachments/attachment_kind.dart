// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// How an attachment should be rendered.
///
/// A deliberately smaller vocabulary than `msgtype`: the timeline only draws
/// two shapes (a preview box or a card), and this enum is what makes that
/// choice exhaustively checked by `switch` — see `message_body.dart`.
enum AttachmentKind {
  /// Drawn as an inline preview box.
  image,

  /// Also a preview box, but with a play glyph and no inline playback.
  video,

  /// A card. Audio gets no waveform or player in this version.
  audio,

  /// A card with a type icon, name, size and a save button.
  file,
}

/// Classifies an event's attachment, or null if it is not one.
///
/// **Deliberately does not check [Event.hasAttachment].** The local echo that
/// `Room.sendFileEvent` injects (room.dart:855-885) carries neither `url` nor
/// `file` until the upload finishes, so gating on `hasAttachment` would render
/// our own image as the text "sent a picture" for a second and then pop into a
/// thumbnail. Classification is about intent, not about whether the bytes have
/// landed yet.
AttachmentKind? attachmentKindOf(Event event) =>
    attachmentKindFor(type: event.type, msgtype: event.messageType);

/// Classifies a file that is being staged, before any event exists for it.
///
/// Routed through the SDK's own [MatrixFile.msgTypeFromMime] so a tray chip can
/// never disagree with the `msgtype` that `sendFileEvent` will actually put on
/// the wire — the two would otherwise be independent guesses about the same
/// file.
AttachmentKind attachmentKindForMimeType(String mimeType) =>
    attachmentKindFor(
      type: EventTypes.Message,
      msgtype: MatrixFile.msgTypeFromMime(mimeType),
    ) ??
    AttachmentKind.file;

/// The rule behind [attachmentKindOf], split out so it can be tested with plain
/// strings rather than a real [Event] — which would need a `Room`, a `Client`
/// and a database. Same reasoning as `computeGroupingFlags`.
@visibleForTesting
AttachmentKind? attachmentKindFor({
  required String type,
  required String msgtype,
}) {
  // Stickers are images that happen to live under their own event type.
  if (type == EventTypes.Sticker) return AttachmentKind.image;
  if (type != EventTypes.Message) return null;

  return switch (msgtype) {
    MessageTypes.Image => AttachmentKind.image,
    MessageTypes.Video => AttachmentKind.video,
    MessageTypes.Audio => AttachmentKind.audio,
    MessageTypes.File => AttachmentKind.file,
    _ => null,
  };
}

/// The caption on a file event, or null if it carries none.
///
/// MSC2530 (spec 1.10) says `filename` holds the real file name and `body`
/// holds the caption *when the two differ*. Clients that predate it — and the
/// SDK's own `sendFileEvent` when no `extraContent` is passed — write
/// `body == filename`, which means "no caption" rather than "a caption that
/// repeats the name".
String? attachmentCaption(Map<String, Object?> content) {
  final filename = content.tryGet<String>('filename');
  final body = content.tryGet<String>('body');

  if (filename == null || body == null) return null;
  if (body == filename || body.trim().isEmpty) return null;
  return body;
}

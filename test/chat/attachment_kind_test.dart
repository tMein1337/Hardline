// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:hardline/core/util/byte_format.dart';
import 'package:hardline/features/chat/attachments/attachment_kind.dart';

void main() {
  group('attachmentKindFor', () {
    test('maps the four file msgtypes', () {
      AttachmentKind? kind(String msgtype) =>
          attachmentKindFor(type: EventTypes.Message, msgtype: msgtype);

      expect(kind(MessageTypes.Image), AttachmentKind.image);
      expect(kind(MessageTypes.Video), AttachmentKind.video);
      expect(kind(MessageTypes.Audio), AttachmentKind.audio);
      expect(kind(MessageTypes.File), AttachmentKind.file);
    });

    test('text-like msgtypes are not attachments', () {
      for (final msgtype in [
        MessageTypes.Text,
        MessageTypes.Notice,
        MessageTypes.Emote,
        MessageTypes.Location,
        MessageTypes.BadEncrypted,
      ]) {
        expect(
          attachmentKindFor(type: EventTypes.Message, msgtype: msgtype),
          isNull,
          reason: '$msgtype must fall through to text rendering',
        );
      }
    });

    test('a sticker is an image regardless of msgtype', () {
      expect(
        attachmentKindFor(
          type: EventTypes.Sticker,
          msgtype: MessageTypes.Sticker,
        ),
        AttachmentKind.image,
      );
    });

    test('non-message event types are not attachments', () {
      expect(
        attachmentKindFor(
          type: EventTypes.RoomMember,
          msgtype: MessageTypes.Image,
        ),
        isNull,
      );
    });

    // The local echo that sendFileEvent injects carries no 'url' and no 'file'
    // until the upload finishes. Classification must not depend on those, or our
    // own image renders as the text "sent a picture" and then pops into a
    // thumbnail a second later.
    test('classifies by msgtype alone, not by whether bytes have landed', () {
      expect(
        attachmentKindFor(type: EventTypes.Message, msgtype: MessageTypes.Image),
        AttachmentKind.image,
        reason: 'a pending upload is still an image',
      );
    });
  });

  group('attachmentKindForMimeType', () {
    test('routes common types through the SDK mime rule', () {
      expect(attachmentKindForMimeType('image/png'), AttachmentKind.image);
      expect(attachmentKindForMimeType('video/mp4'), AttachmentKind.video);
      expect(attachmentKindForMimeType('audio/ogg'), AttachmentKind.audio);
      expect(attachmentKindForMimeType('application/pdf'), AttachmentKind.file);
    });

    test('an unknown type is a plain file rather than an error', () {
      expect(
        attachmentKindForMimeType('application/octet-stream'),
        AttachmentKind.file,
      );
      expect(attachmentKindForMimeType(''), AttachmentKind.file);
    });
  });

  group('attachmentCaption', () {
    test('body different from filename is a caption', () {
      expect(
        attachmentCaption({'filename': 'cat.png', 'body': 'look at this'}),
        'look at this',
      );
    });

    // Every client that predates MSC2530 — and sendFileEvent with no
    // extraContent — writes body == filename. That means "no caption", not "a
    // caption that repeats the name".
    test('body equal to filename is not a caption', () {
      expect(
        attachmentCaption({'filename': 'cat.png', 'body': 'cat.png'}),
        isNull,
      );
    });

    test('a missing filename means there is no caption to find', () {
      expect(attachmentCaption({'body': 'cat.png'}), isNull);
    });

    test('a blank body is not a caption', () {
      expect(
        attachmentCaption({'filename': 'cat.png', 'body': '   '}),
        isNull,
      );
    });

    test('malformed content does not throw', () {
      expect(attachmentCaption({}), isNull);
      expect(attachmentCaption({'filename': 42, 'body': 7}), isNull);
    });
  });

  group('formatBytes', () {
    test('stays in bytes below a kilobyte', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
    });

    test('one decimal below ten, none above', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 12), '12 KB');
    });

    test('climbs through the units', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });
  });
}

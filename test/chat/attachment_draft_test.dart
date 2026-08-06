import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/features/chat/attachments/attachment_draft_controller.dart';
import 'package:matrix_client/features/chat/attachments/attachment_intake.dart';
import 'package:matrix_client/features/chat/attachments/attachment_kind.dart';
import 'package:matrix_client/features/chat/attachments/pending_attachment.dart';

const _roomA = '!a:example.org';
const _roomB = '!b:example.org';

PendingAttachment _attachment(String id, {String? rejection}) =>
    PendingAttachment(
      id: id,
      name: '$id.png',
      mimeType: 'image/png',
      size: 1024,
      kind: AttachmentKind.image,
      source: InMemoryBytes(Uint8List(0)),
      rejection: rejection,
    );

List<PendingAttachment> _many(int count) =>
    [for (var i = 0; i < count; i++) _attachment('a$i')];

void main() {
  late ProviderContainer container;
  late AttachmentDrafts drafts;

  setUp(() {
    container = ProviderContainer();
    drafts = container.read(attachmentDraftsProvider.notifier);
  });

  tearDown(() => container.dispose());

  group('AttachmentDrafts', () {
    test('starts empty', () {
      expect(drafts.forRoom(_roomA), isEmpty);
    });

    test('staging appends in order', () {
      drafts.addAll(_roomA, [_attachment('one')]);
      drafts.addAll(_roomA, [_attachment('two')]);

      expect(
        drafts.forRoom(_roomA).map((a) => a.id),
        ['one', 'two'],
      );
    });

    test('removing takes out only the named attachment', () {
      drafts.addAll(_roomA, [
        _attachment('one'),
        _attachment('two'),
        _attachment('three'),
      ]);
      drafts.remove(_roomA, 'two');

      expect(drafts.forRoom(_roomA).map((a) => a.id), ['one', 'three']);
    });

    test('removing the last one drops the room key entirely', () {
      drafts.addAll(_roomA, [_attachment('one')]);
      drafts.remove(_roomA, 'one');

      expect(
        container.read(attachmentDraftsProvider).containsKey(_roomA),
        isFalse,
        reason: 'an empty entry per visited room would leak',
      );
    });

    test('removing an unknown id is a no-op', () {
      drafts.addAll(_roomA, [_attachment('one')]);
      drafts.remove(_roomA, 'nope');

      expect(drafts.forRoom(_roomA), hasLength(1));
    });

    // The point of a non-autoDispose store: clicking the wrong room in the
    // sidebar must not throw away a staged upload.
    test('rooms keep separate trays', () {
      drafts.addAll(_roomA, [_attachment('a1'), _attachment('a2')]);
      drafts.addAll(_roomB, [_attachment('b1')]);

      expect(drafts.forRoom(_roomA), hasLength(2));
      expect(drafts.forRoom(_roomB), hasLength(1));

      drafts.clear(_roomA);

      expect(drafts.forRoom(_roomA), isEmpty);
      expect(
        drafts.forRoom(_roomB),
        hasLength(1),
        reason: 'sending in one room must not empty another',
      );
    });

    group('the per-message cap', () {
      test('accepts exactly the limit', () {
        final dropped = drafts.addAll(_roomA, _many(kMaxAttachmentsPerMessage));

        expect(dropped, 0);
        expect(drafts.forRoom(_roomA), hasLength(kMaxAttachmentsPerMessage));
      });

      test('truncates an oversized batch and reports the remainder', () {
        final dropped = drafts.addAll(
          _roomA,
          _many(kMaxAttachmentsPerMessage + 3),
        );

        expect(dropped, 3);
        expect(drafts.forRoom(_roomA), hasLength(kMaxAttachmentsPerMessage));
      });

      test('a full tray accepts nothing more', () {
        drafts.addAll(_roomA, _many(kMaxAttachmentsPerMessage));
        final dropped = drafts.addAll(_roomA, [_attachment('extra')]);

        expect(dropped, 1);
        expect(drafts.forRoom(_roomA), hasLength(kMaxAttachmentsPerMessage));
      });
    });
  });

  group('AttachmentIntake', () {
    test('a blob under the limit is accepted', () {
      const intake = AttachmentIntake(maxUploadSize: 1000);
      final staged = intake.fromBytes(
        bytes: Uint8List(500),
        name: 'shot.png',
        mimeType: 'image/png',
      );

      expect(staged.isValid, isTrue);
      expect(staged.kind, AttachmentKind.image);
      expect(staged.size, 500);
    });

    // Rejected rather than dropped: the user has to see *which* file was too
    // big, especially when five were dropped at once.
    test('an oversized blob is staged as rejected, not discarded', () {
      const intake = AttachmentIntake(maxUploadSize: 100);
      final staged = intake.fromBytes(
        bytes: Uint8List(500),
        name: 'shot.png',
        mimeType: 'image/png',
      );

      expect(staged.isValid, isFalse);
      expect(staged.rejection, contains('Too large'));
    });

    test('an unknown server limit blocks nothing', () {
      const intake = AttachmentIntake();
      final staged = intake.fromBytes(
        bytes: Uint8List(50 * 1024 * 1024),
        name: 'big.bin',
      );

      expect(staged.isValid, isTrue);
    });

    test('mime is sniffed from the name when not supplied', () {
      const intake = AttachmentIntake();

      expect(
        intake.fromBytes(bytes: Uint8List(4), name: 'notes.pdf').kind,
        AttachmentKind.file,
      );
      expect(
        intake.fromBytes(bytes: Uint8List(4), name: 'clip.mp4').kind,
        AttachmentKind.video,
      );
    });

    test('staged attachments get distinct ids', () {
      const intake = AttachmentIntake();
      final first = intake.fromBytes(bytes: Uint8List(1), name: 'a.png');
      final second = intake.fromBytes(bytes: Uint8List(1), name: 'a.png');

      expect(first.id, isNot(second.id));
      expect(first, isNot(second));
    });
  });

  group('clipboardImageName', () {
    test('is shaped like a Windows screenshot name', () {
      expect(
        clipboardImageName('image/png', now: DateTime(2026, 8, 6, 14, 32, 5)),
        'Screenshot 2026-08-06 14-32-05.png',
      );
    });

    test('falls back to .bin for an unrecognised type', () {
      expect(
        clipboardImageName('image/nonsense', now: DateTime(2026, 1, 2, 3, 4, 5)),
        'Screenshot 2026-01-02 03-04-05.bin',
      );
    });
  });
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/mentions.dart';
import 'package:hardline/features/chat/message_content.dart';
import 'package:matrix/matrix.dart' hide Visibility;

import '../support/fake_matrix.dart';

const _alice = MentionCandidate(
  userId: '@alice:example.org',
  displayName: 'Alice',
);
const _bob = MentionCandidate(userId: '@bob:example.org', displayName: 'Bob');

void main() {
  group('textMessageContent', () {
    test('an ordinary message carries no mention block', () {
      final content = textMessageContent('hello');

      expect(content['body'], 'hello');
      expect(content['msgtype'], MessageTypes.Text);
      expect(content.containsKey('m.mentions'), isFalse);
    });

    test('a reply mentions whoever it answers, without naming them', () {
      final content = textMessageContent(
        'agreed',
        alsoMention: {'@alice:example.org'},
      );

      expect(content['m.mentions'], {
        'user_ids': ['@alice:example.org'],
      });
      // Nobody is named in the text, so there is no pill to draw.
      expect(content.containsKey('formatted_body'), isFalse);
    });
  });

  group('editContent', () {
    test('has the shape the spec asks for', () {
      final content = editContent(
        textMessageContent('fixed'),
        originalEventId: r'$original',
      );

      expect(content['body'], '* fixed');
      expect(content['m.new_content'], containsPair('body', 'fixed'));
      expect(content['m.relates_to'], {
        'rel_type': RelationshipTypes.edit,
        'event_id': r'$original',
      });
    });

    test('notifies only people the edit newly names', () {
      final content = editContent(
        textMessageContent('@Alice and @Bob', candidates: const [_alice, _bob]),
        originalEventId: r'$original',
        previouslyMentioned: {'@alice:example.org'},
      );

      expect(content['m.mentions'], {
        'user_ids': ['@bob:example.org'],
      });
      // The new content still names both: that is what the message says now.
      final newContent = content['m.new_content']! as Map;
      expect(newContent['m.mentions'], {
        'user_ids': ['@alice:example.org', '@bob:example.org'],
      });
      expect(content['formatted_body'], startsWith('* '));
    });

    test('a typo fix notifies nobody again', () {
      final content = editContent(
        textMessageContent('@Alice hello', candidates: const [_alice]),
        originalEventId: r'$original',
        previouslyMentioned: {'@alice:example.org'},
      );

      expect(content['m.mentions'], isEmpty);
    });
  });

  group('isEditableByMe', () {
    late FakeMatrixClient client;
    late Room room;

    setUp(() {
      client = FakeMatrixClient();
      room = client.addRoom('!a:example.org');
    });

    Event message({String? sender, String msgtype = MessageTypes.Text}) =>
        Event(
          content: {'msgtype': msgtype, 'body': 'hi'},
          type: EventTypes.Message,
          eventId: r'$1',
          senderId: sender ?? client.me,
          originServerTs: DateTime(2026),
          room: room,
        );

    test('our own text messages can be edited', () {
      expect(isEditableByMe(message()), isTrue);
      expect(isEditableByMe(message(msgtype: MessageTypes.Emote)), isTrue);
    });

    test("somebody else's cannot", () {
      expect(isEditableByMe(message(sender: '@alice:example.org')), isFalse);
    });

    test('attachments cannot', () {
      expect(isEditableByMe(message(msgtype: MessageTypes.Image)), isFalse);
    });
  });
}

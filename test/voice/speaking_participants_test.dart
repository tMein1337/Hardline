// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/speaking_participants.dart';

void main() {
  const room = '!channel:example.org';
  const alice = '@alice:example.org';
  const bob = '@bob:example.org';

  group('fromIdentities', () {
    test('reduces LiveKit identities to the people behind them', () {
      final speaking = SpeakingParticipants.fromIdentities(room, [
        '$alice:LQTQHXJKCZ',
        '$bob:ABCDEFGH',
      ]);

      expect(speaking.userIds, {alice, bob});
      expect(speaking.roomId, room);
    });

    // One person, two microphones, one face on screen. Whichever device the
    // audio came from, there is one avatar to light up.
    test('collapses somebody connected from two devices', () {
      final speaking = SpeakingParticipants.fromIdentities(room, [
        '$alice:LAPTOP',
        '$alice:DESKTOP',
      ]);

      expect(speaking.userIds, {alice});
    });

    test('nobody speaking is nobody speaking', () {
      expect(
        SpeakingParticipants.fromIdentities(room, const []).userIds,
        isEmpty,
      );
    });
  });

  group('contains', () {
    final speaking = SpeakingParticipants.fromIdentities(room, [
      '$alice:LQTQHXJKCZ',
    ]);

    test('answers for the person asked about', () {
      expect(speaking.contains(alice), isTrue);
      expect(speaking.contains(bob), isFalse);
    });

    test('scoped to a room, answers only for that room', () {
      expect(speaking.contains(alice, inRoom: room), isTrue);
      expect(
        speaking.contains(alice, inRoom: '!elsewhere:example.org'),
        isFalse,
      );
    });

    // What the user footer asks: it is not tied to a room, and the question is
    // only whether the microphone is picking us up.
    test('unscoped, answers for whichever call we are in', () {
      expect(speaking.contains(alice, inRoom: null), isTrue);
    });

    // A ring left lit on a call that has ended says somebody is talking to you
    // when nobody is even connected.
    test('silence answers no to everything', () {
      const silent = SpeakingParticipants.silent();

      expect(silent.contains(alice), isFalse);
      expect(silent.contains(alice, inRoom: room), isFalse);
    });
  });

  group('equality', () {
    // The load-bearing property. `ValueNotifier` only fires when the value
    // differs, so a steady report of "alice is still talking" has to compare
    // equal or every avatar on screen repaints several times a second.
    test('the same speakers in a different order are the same value', () {
      expect(
        SpeakingParticipants.fromIdentities(room, ['$alice:A', '$bob:B']),
        SpeakingParticipants.fromIdentities(room, ['$bob:B', '$alice:A']),
      );
    });

    test('two devices of one person are the same value as one', () {
      expect(
        SpeakingParticipants.fromIdentities(room, ['$alice:LAPTOP']),
        SpeakingParticipants.fromIdentities(room, [
          '$alice:LAPTOP',
          '$alice:DESKTOP',
        ]),
      );
    });

    test('a different speaker is a different value', () {
      expect(
        SpeakingParticipants.fromIdentities(room, ['$alice:A']),
        isNot(SpeakingParticipants.fromIdentities(room, ['$bob:B'])),
      );
    });

    test('the same speaker in another room is a different value', () {
      expect(
        SpeakingParticipants.fromIdentities(room, ['$alice:A']),
        isNot(
          SpeakingParticipants.fromIdentities('!other:example.org', [
            '$alice:A',
          ]),
        ),
      );
    });

    test('hash codes agree with equality', () {
      expect(
        SpeakingParticipants.fromIdentities(room, [
          '$alice:A',
          '$bob:B',
        ]).hashCode,
        SpeakingParticipants.fromIdentities(room, [
          '$bob:B',
          '$alice:A',
        ]).hashCode,
      );
    });
  });
}

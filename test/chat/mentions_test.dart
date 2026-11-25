// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/mentions.dart';
import 'package:hardline/features/chat/message_links.dart';

const _alice = MentionCandidate(
  userId: '@alice:example.org',
  displayName: 'Alice',
);
const _aliceSmith = MentionCandidate(
  userId: '@asmith:example.org',
  displayName: 'Alice Smith',
);
const _bob = MentionCandidate(userId: '@bob:example.org', displayName: 'Bob');

void main() {
  group('mentionQuery', () {
    test('finds the run being typed', () {
      expect(mentionQuery('hi @al', 6), (query: 'al', start: 3));
    });

    test('matches an empty query so the list opens on the @ itself', () {
      expect(mentionQuery('hi @', 4), (query: '', start: 3));
    });

    test('matches at the very start of the message', () {
      expect(mentionQuery('@bo', 3), (query: 'bo', start: 0));
    });

    // Otherwise typing an email address would open a people picker.
    test('ignores an @ that does not start a word', () {
      expect(mentionQuery('mail me at bob@example.org', 26), isNull);
    });

    // The popup has to close once the name is done, or it would hang over the
    // rest of the sentence offering completions for words already past.
    test('closes once whitespace is typed', () {
      expect(mentionQuery('hi @alice how', 13), isNull);
    });

    test('is null when there is no @ at all', () {
      expect(mentionQuery('hello there', 11), isNull);
    });

    test('reads from the caret, not the end of the text', () {
      // Caret sits right after "@al", with more text beyond it.
      expect(mentionQuery('hi @al rest', 6), (query: 'al', start: 3));
    });
  });

  group('rankMentions', () {
    test('offers everybody for an empty query', () {
      expect(rankMentions(const [_alice, _bob], ''), hasLength(2));
    });

    test('puts a prefix match above a contained one', () {
      const michal = MentionCandidate(
        userId: '@michal:example.org',
        displayName: 'Michal',
      );
      final ranked = rankMentions(const [michal, _alice], 'al');
      expect(ranked.first.userId, _alice.userId);
    });

    test('matches the id localpart as well as the name', () {
      const odd = MentionCandidate(
        userId: '@zebra:example.org',
        displayName: 'Q',
      );
      expect(rankMentions(const [odd], 'zeb'), hasLength(1));
    });

    test('is case insensitive', () {
      expect(rankMentions(const [_alice], 'ALI'), hasLength(1));
    });

    test('honours the limit', () {
      final many = [
        for (var i = 0; i < 30; i++)
          MentionCandidate(userId: '@u$i:example.org', displayName: 'User $i'),
      ];
      expect(rankMentions(many, '', limit: 5), hasLength(5));
    });
  });

  group('applyMention', () {
    test('replaces the run and leaves a trailing space', () {
      final result = applyMention(
        text: 'hi @al',
        start: 3,
        cursor: 6,
        candidate: _alice,
      );
      expect(result.text, 'hi @Alice ');
      expect(result.cursor, 'hi @Alice '.length);
    });

    test('keeps the text after the caret', () {
      final result = applyMention(
        text: 'hi @al there',
        start: 3,
        cursor: 6,
        candidate: _alice,
      );
      expect(result.text, 'hi @Alice  there');
    });
  });

  group('mentionedUserIds', () {
    test('finds a named person', () {
      expect(mentionedUserIds('hi @Alice', const [_alice]), {_alice.userId});
    });

    test('is empty when nobody is named', () {
      expect(mentionedUserIds('hi there', const [_alice]), isEmpty);
    });

    // "Alice" is a prefix of "Alice Smith", and matching the short one first
    // would leave "Smith" outside the pill and ping the wrong person.
    test('prefers the longer name when one contains the other', () {
      final found = mentionedUserIds('hi @Alice Smith', const [
        _alice,
        _aliceSmith,
      ]);
      expect(found, contains(_aliceSmith.userId));
    });

    test('finds several', () {
      expect(mentionedUserIds('@Alice and @Bob', const [_alice, _bob]), {
        _alice.userId,
        _bob.userId,
      });
    });
  });

  group('mentionsBlock', () {
    // An ordinary message must stay byte-for-byte what it was.
    test('is empty when nobody is mentioned', () {
      expect(mentionsBlock(const {}), isEmpty);
    });

    test('lists the ids, sorted so the output is stable', () {
      expect(mentionsBlock({'@b:x.org', '@a:x.org'}), {
        'user_ids': ['@a:x.org', '@b:x.org'],
      });
    });
  });

  group('splitMentions', () {
    test('splits a plain run around the mention', () {
      final spans = splitMentions(splitBodyLinks('hi @Alice there'), {
        _alice.userId: 'Alice',
      });

      expect(spans, [
        const BodySpan.text('hi '),
        BodySpan.mention('@Alice', _alice.userId),
        const BodySpan.text(' there'),
      ]);
    });

    test('returns the spans untouched when nobody is mentioned', () {
      final links = splitBodyLinks('hi there');
      expect(splitMentions(links, const {}), same(links));
    });

    // A URL that happens to contain a name is still a URL.
    test('does not split inside a link', () {
      final spans = splitMentions(
        splitBodyLinks('see https://example.org/@Alice'),
        {_alice.userId: 'Alice'},
      );
      expect(spans.where((s) => s.isMention), isEmpty);
    });

    test('handles the same person named twice', () {
      final spans = splitMentions(splitBodyLinks('@Alice and @Alice'), {
        _alice.userId: 'Alice',
      });
      expect(spans.where((s) => s.isMention), hasLength(2));
    });

    test('reassembles to the original body', () {
      const body = 'hi @Alice and @Bob, see https://example.org';
      final spans = splitMentions(splitBodyLinks(body), {
        _alice.userId: 'Alice',
        _bob.userId: 'Bob',
      });
      expect(spans.map((s) => s.text).join(), body);
    });
  });
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/chat_prefs.dart';
import 'package:hardline/features/chat/message_drafts.dart';

void main() {
  group('MessageDrafts', () {
    late ProviderContainer container;
    late MessageDrafts drafts;

    setUp(() {
      container = ProviderContainer();
      drafts = container.read(messageDraftsProvider.notifier);
    });

    tearDown(() => container.dispose());

    test('starts empty', () {
      expect(drafts.forRoom('!a:example.org'), '');
      expect(drafts.hasDraft('!a:example.org'), isFalse);
    });

    test('keeps a draft per room, without leaking between them', () {
      drafts.set('!a:example.org', 'hello');
      drafts.set('!b:example.org', 'goodbye');

      expect(drafts.forRoom('!a:example.org'), 'hello');
      expect(drafts.forRoom('!b:example.org'), 'goodbye');
    });

    // Storing '' would leave an entry behind for every room ever opened, and
    // make `hasDraft` a value check rather than a key check.
    test('drops the entry when the text is emptied', () {
      drafts.set('!a:example.org', 'hello');
      drafts.set('!a:example.org', '');

      expect(drafts.hasDraft('!a:example.org'), isFalse);
      expect(container.read(messageDraftsProvider), isEmpty);
    });

    test('clear forgets one room and leaves the others', () {
      drafts.set('!a:example.org', 'hello');
      drafts.set('!b:example.org', 'goodbye');
      drafts.clear('!a:example.org');

      expect(drafts.hasDraft('!a:example.org'), isFalse);
      expect(drafts.forRoom('!b:example.org'), 'goodbye');
    });

    test('clearAll forgets everything', () {
      drafts.set('!a:example.org', 'hello');
      drafts.set('!b:example.org', 'goodbye');
      drafts.clearAll();

      expect(container.read(messageDraftsProvider), isEmpty);
    });

    // The composer writes on every keystroke, so an unchanged value must not
    // produce a new state object and rebuild the panel.
    test('does not churn state when nothing changed', () {
      drafts.set('!a:example.org', 'hello');
      final first = container.read(messageDraftsProvider);
      drafts.set('!a:example.org', 'hello');

      expect(identical(container.read(messageDraftsProvider), first), isTrue);
    });

    test('clearing a room that has no draft is a no-op', () {
      final before = container.read(messageDraftsProvider);
      drafts.clear('!nothing:example.org');
      expect(identical(container.read(messageDraftsProvider), before), isTrue);
    });

    test('roomDraftProvider reads one room', () {
      drafts.set('!a:example.org', 'hello');

      expect(container.read(roomDraftProvider('!a:example.org')), 'hello');
      expect(container.read(roomDraftProvider('!b:example.org')), '');
    });
  });

  group('ChatPrefsState', () {
    test('keeps drafts by default', () {
      expect(const ChatPrefsState().keepDrafts, isTrue);
    });

    test('round-trips through JSON', () {
      const off = ChatPrefsState(keepDrafts: false);
      expect(ChatPrefsState.fromJson(off.toJson()), off);
    });

    // Unlike the security prefs, the fallback here is the *useful* answer
    // rather than the careful one — nothing about a draft is a safety
    // question, and losing what somebody typed is the only real failure.
    test('falls back to keeping drafts when the value is unreadable', () {
      for (final json in <Map<String, Object?>>[
        {},
        {'keepDrafts': 'yes'},
        {'keepDrafts': 1},
        {'keepDrafts': null},
      ]) {
        expect(
          ChatPrefsState.fromJson(json).keepDrafts,
          isTrue,
          reason: '$json',
        );
      }
    });

    test('has value equality', () {
      expect(const ChatPrefsState(), const ChatPrefsState());
      expect(
        const ChatPrefsState(keepDrafts: false),
        isNot(const ChatPrefsState()),
      );
    });
  });
}

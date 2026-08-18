// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/accounts/account_entry.dart';

void main() {
  const alice = AccountEntry(
    storageKey: kDefaultStorageKey,
    userId: '@alice:example.org',
    homeserver: 'example.org',
    displayName: 'Alice',
    avatarUrl: 'mxc://example.org/abc',
  );
  const bob = AccountEntry(
    storageKey: 'k2x9',
    userId: '@bob:example.org',
    homeserver: 'example.org',
  );

  group('AccountEntry', () {
    test('round-trips through JSON', () {
      expect(AccountEntry.fromJson(alice.toJson()), alice);
      expect(AccountEntry.fromJson(bob.toJson()), bob);
    });

    test('falls back to the localpart when no display name is cached', () {
      expect(bob.label, 'bob');
      expect(alice.label, 'Alice');
    });

    test('rejects entries with nothing to identify them by', () {
      expect(AccountEntry.fromJson(null), isNull);
      expect(AccountEntry.fromJson('nonsense'), isNull);
      expect(AccountEntry.fromJson({'userId': '@a:b'}), isNull);
      expect(AccountEntry.fromJson({'storageKey': 'k'}), isNull);
      expect(
        AccountEntry.fromJson({'storageKey': '', 'userId': '@a:b'}),
        isNull,
      );
    });
  });

  group('AccountsState', () {
    test('round-trips through JSON', () {
      const state = AccountsState(
        entries: [alice, bob],
        activeStorageKey: 'k2x9',
      );
      expect(AccountsState.fromJson(state.toJson()), state);
    });

    // A corrupt row must cost one account, not the ability to start.
    test('drops unparseable entries and keeps the rest', () {
      final state = AccountsState.fromJson({
        'entries': [
          alice.toJson(),
          {'userId': '@broken:example.org'},
          bob.toJson(),
        ],
        'active': kDefaultStorageKey,
      });

      expect(state.entries, [alice, bob]);
      expect(state.activeStorageKey, kDefaultStorageKey);
    });

    // Nothing downstream can open a database for an account that is not there,
    // so the active key must never survive its entry.
    test('repoints active when it names an entry that did not survive', () {
      final state = AccountsState.fromJson({
        'entries': [bob.toJson()],
        'active': 'gone',
      });

      expect(state.activeStorageKey, bob.storageKey);
    });

    test('is empty for a blob with nothing usable in it', () {
      final state = AccountsState.fromJson({'entries': 'not a list'});
      expect(state.entries, isEmpty);
      expect(state.activeStorageKey, isNull);
      expect(state.isEmpty, isTrue);
    });

    test('removing the active account is not representable as a dangling key', () {
      const state = AccountsState(
        entries: [alice, bob],
        activeStorageKey: kDefaultStorageKey,
      );
      expect(state.active, alice);
      expect(state.byUserId('@bob:example.org'), bob);
      expect(state.byKey('nope'), isNull);
    });
  });

  group('generateStorageKey', () {
    test('produces filename-safe, non-empty, distinct keys', () {
      final keys = {for (var i = 0; i < 200; i++) generateStorageKey()};

      expect(keys.length, greaterThan(190), reason: 'keys should not collide');
      for (final key in keys) {
        expect(key, isNotEmpty);
        expect(key, matches(RegExp(r'^[0-9a-z]+$')));
      }
    });
  });
}

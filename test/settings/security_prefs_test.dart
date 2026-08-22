// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/settings/security_prefs.dart';

void main() {
  group('SecurityPrefsState', () {
    // The whole point of the setting. A build that shipped with this off by
    // accident would open links from strangers on one click.
    test('asks before opening a link until told otherwise', () {
      expect(const SecurityPrefsState().confirmLinks, isTrue);
    });

    test('round-trips through JSON', () {
      const off = SecurityPrefsState(confirmLinks: false);

      expect(SecurityPrefsState.fromJson(off.toJson()), off);
      expect(
        SecurityPrefsState.fromJson(const SecurityPrefsState().toJson()),
        const SecurityPrefsState(),
      );
    });

    // A safeguard may only be switched off by somebody choosing to. Anything
    // the app cannot read resolves the careful way, not the permissive one.
    test('an unreadable value resolves to asking, not to opening', () {
      for (final json in <Map<String, Object?>>[
        {},
        {'confirmLinks': null},
        {'confirmLinks': 'false'},
        {'confirmLinks': 0},
        {'somethingElse': true},
      ]) {
        expect(
          SecurityPrefsState.fromJson(json).confirmLinks,
          isTrue,
          reason: '$json',
        );
      }
    });

    test('copyWith changes only what it is given', () {
      const on = SecurityPrefsState();

      expect(on.copyWith().confirmLinks, isTrue);
      expect(on.copyWith(confirmLinks: false).confirmLinks, isFalse);
    });

    test('equality is by value', () {
      expect(const SecurityPrefsState(), const SecurityPrefsState());
      expect(
        const SecurityPrefsState(),
        isNot(const SecurityPrefsState(confirmLinks: false)),
      );
    });
  });
}

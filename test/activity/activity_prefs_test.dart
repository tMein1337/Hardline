// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/activity/activity_prefs_state.dart';

void main() {
  group('ActivityPrefsState', () {
    test('round-trips through JSON', () {
      const state = ActivityPrefsState(
        following: {'@bob:example.org', '@carol:example.org'},
        recentWindow: Duration(hours: 3),
        showVoice: false,
        showActive: true,
        showMessages: false,
        backfillOnLaunch: true,
      );

      expect(ActivityPrefsState.fromJson(state.toJson()), state);
    });

    test('an empty blob is the defaults', () {
      expect(
        ActivityPrefsState.fromJson(const {}),
        const ActivityPrefsState.empty(),
      );
    });

    // A blob written before a toggle existed must not arrive with that list
    // switched off — the user never chose that, and an empty page with no
    // explanation is the worst possible reading of a missing key.
    test('missing toggles default to on, missing backfill to off', () {
      final state = ActivityPrefsState.fromJson(const {
        'following': ['@bob:example.org'],
      });

      expect(state.showVoice, isTrue);
      expect(state.showActive, isTrue);
      expect(state.showMessages, isTrue);
      expect(state.backfillOnLaunch, isFalse);
    });

    // Clamped at parse rather than at use: a hand-edited window of a year makes
    // "recently active" mean "ever", with nothing on screen to explain why the
    // list never shrinks.
    test('the window is clamped at parse time', () {
      final tooLong = ActivityPrefsState.fromJson(const {
        'recentWindowMs': 1000 * 60 * 60 * 24 * 365,
      });
      expect(tooLong.recentWindow, kMaxRecentWindow);

      final tooShort = ActivityPrefsState.fromJson(const {
        'recentWindowMs': 1,
      });
      expect(tooShort.recentWindow, kMinRecentWindow);
    });

    test('garbage types fall back rather than throwing', () {
      final state = ActivityPrefsState.fromJson(const {
        'following': 'not a list',
        'recentWindowMs': 'not a number',
        'showVoice': 'maybe',
      });

      expect(state.following, isEmpty);
      expect(state.recentWindow, kDefaultRecentWindow);
      expect(state.showVoice, isTrue);
    });

    test('non-string entries in the follow list are dropped', () {
      final state = ActivityPrefsState.fromJson(const {
        'following': ['@bob:example.org', 42, null, ''],
      });

      expect(state.following, {'@bob:example.org'});
    });

    // The set is stored sorted so saving an unchanged state does not rewrite
    // the preference with different bytes every time.
    test('the stored follow list is ordered', () {
      const state = ActivityPrefsState(
        following: {'@carol:example.org', '@alice:example.org'},
      );

      expect(state.toJson()['following'], [
        '@alice:example.org',
        '@carol:example.org',
      ]);
    });

    test('equality ignores the order of the follow set', () {
      const a = ActivityPrefsState(following: {'@alice:example.org', '@bob:example.org'});
      const b = ActivityPrefsState(following: {'@bob:example.org', '@alice:example.org'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every offered window survives a round trip unclamped', () {
      for (final window in kRecentWindowChoices) {
        final state = ActivityPrefsState.fromJson(
          ActivityPrefsState(recentWindow: window).toJson(),
        );
        expect(state.recentWindow, window);
      }
    });
  });
}

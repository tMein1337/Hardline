// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/util/time_format.dart';

void main() {
  final now = DateTime(2026, 8, 11, 14, 30);

  String ago(Duration elapsed) =>
      formatRelativeTime(now.subtract(elapsed), now: now);

  group('formatRelativeTime', () {
    test('anything under a minute is "just now"', () {
      expect(ago(Duration.zero), 'just now');
      expect(ago(const Duration(seconds: 59)), 'just now');
    });

    // Clocks skewed against the homeserver's put events a few seconds in the
    // future. "in 4 seconds" reads as a bug; "just now" is true enough.
    test('a timestamp in the future is "just now" rather than negative', () {
      expect(ago(const Duration(seconds: -20)), 'just now');
    });

    test('minutes below an hour', () {
      expect(ago(const Duration(minutes: 1)), '1 min ago');
      expect(ago(const Duration(minutes: 59)), '59 min ago');
    });

    test('hours below a day', () {
      expect(ago(const Duration(hours: 1)), '1 h ago');
      expect(ago(const Duration(hours: 23)), '23 h ago');
    });

    test('the previous calendar day is "yesterday"', () {
      expect(ago(const Duration(hours: 25)), 'yesterday');
    });

    test('anything older is a date', () {
      expect(ago(const Duration(days: 4)), '07/08/2026');
    });

    // A message at 23:50 read at 00:10 is 20 minutes old and yesterday's. The
    // elapsed time wins, because "yesterday" for something 20 minutes ago
    // reads as much staler than it is.
    test('elapsed time outranks the calendar boundary', () {
      final justAfterMidnight = DateTime(2026, 8, 11, 0, 10);
      final lateLastNight = DateTime(2026, 8, 10, 23, 50);

      expect(
        formatRelativeTime(lateLastNight, now: justAfterMidnight),
        '20 min ago',
      );
    });
  });
}

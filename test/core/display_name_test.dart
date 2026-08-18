// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/util/display_name.dart';

String _c(int code) => String.fromCharCode(code);

void main() {
  group('real names are left alone', () {
    test('plain names pass through', () {
      expect(displaySafeName('Alice'), 'Alice');
      expect(displaySafeName('Alice Example'), 'Alice Example');
      expect(displaySafeName('room: general'), 'room: general');
    });

    // The point of stripping only the *override* controls: right-to-left
    // scripts are ordinary text and must keep working.
    test('right-to-left scripts are untouched', () {
      expect(displaySafeName('شبكة'), 'شبكة');
      expect(displaySafeName('דוד'), 'דוד');
      expect(displaySafeName('Ola Nordmann'), 'Ola Nordmann');
    });

    test('emoji and CJK survive', () {
      expect(displaySafeName('チャット'), 'チャット');
      expect(displaySafeName('team 🚀'), 'team 🚀');
    });

    test('directional marks are kept, being weak and often legitimate', () {
      final withMark = 'a${_c(0x200F)}b';
      expect(displaySafeName(withMark), withMark);
    });
  });

  group('impersonation via reordering', () {
    test('a right-to-left override is removed', () {
      final spoof = 'admin${_c(0x202E)}eciwt';
      final safe = displaySafeName(spoof);

      expect(safe.contains(_c(0x202E)), isFalse);
      expect(safe, 'admineciwt');
    });

    test('every override, embedding and isolate control is removed', () {
      for (final code in [
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
        0x2066, 0x2067, 0x2068, 0x2069,
      ]) {
        expect(
          displaySafeName('a${_c(code)}b'),
          'ab',
          reason: 'U+${code.toRadixString(16)}',
        );
      }
    });

    test('zero-width characters cannot pad a name invisibly', () {
      expect(displaySafeName('Ali${_c(0x200B)}ce'), 'Alice');
      expect(displaySafeName('${_c(0xFEFF)}Alice'), 'Alice');
    });
  });

  group('layout cannot be attacked', () {
    test('newlines and tabs collapse to a single space', () {
      expect(displaySafeName('Alice\nExample'), 'Alice Example');
      expect(displaySafeName('Alice\t\tExample'), 'Alice Example');
      expect(displaySafeName('a\n\n\n\n\nb'), 'a b');
    });

    test('a name of many blank lines does not become a tall row', () {
      expect(displaySafeName('\n' * 500), 'Unknown');
    });

    test('surrounding whitespace is trimmed', () {
      expect(displaySafeName('   Alice   '), 'Alice');
    });

    test('control characters are dropped', () {
      expect(displaySafeName('Ali${_c(0x00)}ce'), 'Alice');
      expect(displaySafeName('Ali${_c(0x1B)}ce'), 'Alice');
      expect(displaySafeName('Ali${_c(0x7F)}ce'), 'Alice');
    });

    test('an enormous name is clamped and visibly truncated', () {
      final safe = displaySafeName('A' * 5000);

      expect(safe.length, lessThanOrEqualTo(kMaxDisplayNameLength));
      expect(safe.endsWith('…'), isTrue);
    });
  });

  group('always returns something drawable', () {
    test('null and empty use the fallback', () {
      expect(displaySafeName(null), 'Unknown');
      expect(displaySafeName(''), 'Unknown');
      expect(displaySafeName('    '), 'Unknown');
    });

    test('a name of nothing but invisible characters uses the fallback', () {
      expect(displaySafeName('${_c(0x202E)}${_c(0x200B)}'), 'Unknown');
    });

    test('the fallback is configurable', () {
      expect(displaySafeName(null, fallback: 'No one'), 'No one');
    });

    test('output is single-line, bounded and non-empty for hostile input', () {
      final inputs = [
        '', '   ', '\n\n\n', _c(0x202E), '${_c(0x202E)}x' * 200,
        'A' * 10000, 'a\nb\tc', '${_c(0x00)}${_c(0x1F)}', '🚀' * 400,
      ];

      for (final input in inputs) {
        final safe = displaySafeName(input);
        expect(safe, isNotEmpty);
        expect(safe.contains('\n'), isFalse);
        expect(safe.contains('\t'), isFalse);
        expect(safe.length, lessThanOrEqualTo(kMaxDisplayNameLength));
      }
    });
  });
}

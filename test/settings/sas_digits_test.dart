// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/settings/verification/sas_digits.dart';

void main() {
  group('sasDigitGroups', () {
    test('regroups the twelve digits into four groups of three', () {
      expect(sasDigitGroups([1234, 5678, 9012]), [
        '123',
        '456',
        '789',
        '012',
      ]);
    });

    // The regrouping is only safe because it does not touch the digits. An
    // Element user reading "1234 5678 9012" and one reading "123 456 789 012"
    // have to be comparing the same stream, or the whole check is theatre.
    test('preserves the digit stream Element renders as three groups of four', () {
      const numbers = [1000, 9191, 4242];
      expect(sasDigitGroups(numbers).join(), numbers.join());
    });

    test('keeps leading zeros that a numeric join would not lose', () {
      // 1000 is the protocol minimum, so a group can legitimately start with
      // zeros carried over from the previous number.
      expect(sasDigitGroups([1000, 1000, 1000]), [
        '100',
        '010',
        '001',
        '000',
      ]);
    });

    test('handles both ends of the protocol range', () {
      expect(sasDigitGroups([kSasMin, kSasMin, kSasMin]).join().length, 12);
      expect(sasDigitGroups([kSasMax, kSasMax, kSasMax]), [
        '919',
        '191',
        '919',
        '191',
      ]);
    });

    // A future SDK change producing a different shape must fail loudly rather
    // than render a short code that still looks like something to compare.
    test('asserts on anything that is not three in-range numbers', () {
      expect(() => sasDigitGroups([1234, 5678]), throwsAssertionError);
      expect(() => sasDigitGroups([1234, 5678, 9012, 3456]),
          throwsAssertionError);
      expect(() => sasDigitGroups([999, 5678, 9012]), throwsAssertionError);
      expect(() => sasDigitGroups([1234, 5678, 9999]), throwsAssertionError);
      expect(() => sasDigitGroups(const []), throwsAssertionError);
    });
  });
}

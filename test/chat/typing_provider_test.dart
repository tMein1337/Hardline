// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/typing_provider.dart';

void main() {
  group('typingSentence', () {
    test('says nothing when nobody is typing', () {
      expect(typingSentence(const []), isNull);
    });

    test('names one person', () {
      expect(typingSentence(const ['Alice']), 'Alice is typing…');
    });

    test('names two', () {
      expect(
        typingSentence(const ['Alice', 'Bob']),
        'Alice and Bob are typing…',
      );
    });

    test('names three', () {
      expect(
        typingSentence(const ['Alice', 'Bob', 'Carol']),
        'Alice, Bob and Carol are typing…',
      );
    });

    // Past three the line gets long enough to wrap, and a wrapping indicator
    // would change the strip's height and shift the composer under somebody's
    // cursor. Counting stops being useful well before it stops fitting.
    test('stops naming people past three', () {
      expect(
        typingSentence(const ['Alice', 'Bob', 'Carol', 'Dave']),
        'Several people are typing…',
      );
      expect(
        typingSentence(const ['A', 'B', 'C', 'D', 'E', 'F']),
        'Several people are typing…',
      );
    });
  });
}

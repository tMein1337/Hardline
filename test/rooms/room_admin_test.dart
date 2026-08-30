// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/rooms/room_admin.dart';

void main() {
  group('DismantleStep', () {
    // The order is the whole safety property: each step has to survive the
    // next one failing. Releasing first means a space that half-dismantles
    // still leaves its rooms usable; leaving last means every step above still
    // has the power level it needs.
    test('runs from detaching to leaving', () {
      expect(DismantleStep.values, [
        DismantleStep.detaching,
        DismantleStep.removingAddress,
        DismantleStep.removingMembers,
        DismantleStep.leaving,
      ]);
    });

    test('every step says what it is doing', () {
      for (final step in DismantleStep.values) {
        expect(step.label, isNotEmpty, reason: step.name);
      }
    });
  });
}

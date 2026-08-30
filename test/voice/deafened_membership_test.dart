// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/matrix_rtc_membership.dart';

/// A minimal well-formed membership body, so each test can vary one key.
Map<String, Object?> _content({Object? deafened}) => {
  'application': kCallApplication,
  'device_id': 'DEVICE',
  'membershipID': '@a:example.org:DEVICE',
  'created_ts': DateTime.now().millisecondsSinceEpoch,
  'expires': 3600000,
  kDeafenedKey: ?deafened,
};

void main() {
  group('the deafened flag on a call membership', () {
    test('is false when nothing published it', () {
      final membership = MatrixRtcMembership.fromContent(
        content: _content(),
        userId: '@a:example.org',
      );
      expect(membership, isNotNull);
      expect(membership!.deafened, isFalse);
    });

    test('is true when published as true', () {
      final membership = MatrixRtcMembership.fromContent(
        content: _content(deafened: true),
        userId: '@a:example.org',
      );
      expect(membership!.deafened, isTrue);
    });

    test('is false when published as false', () {
      final membership = MatrixRtcMembership.fromContent(
        content: _content(deafened: false),
        userId: '@a:example.org',
      );
      expect(membership!.deafened, isFalse);
    });

    // Every other client omits this key entirely, and a future one might put
    // something unrelated under a name that collides. Absence and nonsense
    // both have to mean "not deafened" — never "unknown", and never a throw,
    // because one malformed event must not take down a room's participant
    // list.
    test('treats anything that is not the literal true as not deafened', () {
      for (final nonsense in <Object>[
        'true',
        1,
        0,
        <String, Object?>{},
        <Object>[],
      ]) {
        final membership = MatrixRtcMembership.fromContent(
          content: _content(deafened: nonsense),
          userId: '@a:example.org',
        );
        expect(
          membership?.deafened,
          isFalse,
          reason: 'for ${nonsense.runtimeType} $nonsense',
        );
      }
    });

    // Leaving is an empty content body, and that must still parse to null
    // rather than to a deafened ghost.
    test('does not resurrect a membership that was withdrawn', () {
      expect(
        MatrixRtcMembership.fromContent(
          content: const {},
          userId: '@a:example.org',
        ),
        isNull,
      );
    });

    test('the key is namespaced, so it cannot collide with the MSC', () {
      expect(kDeafenedKey, startsWith('io.hardline.'));
      expect(kDeafenedKey, isNot(startsWith('m.')));
    });
  });
}

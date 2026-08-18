// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/matrix_rtc_membership.dart';

/// A membership content blob in the shape Element Call actually publishes,
/// taken from a real `org.matrix.msc3401.call.member` event.
Map<String, Object?> contentFixture({
  int? createdTs,
  int expires = 14400000,
  Object? foci,
}) => {
  'application': 'm.call',
  'call_id': '',
  'scope': 'm.room',
  'device_id': 'YERAQSHKJW',
  'membershipID': '@alice:example.org:YERAQSHKJW',
  'created_ts': createdTs ?? DateTime.now().millisecondsSinceEpoch,
  'expires': expires,
  'm.call.intent': 'audio',
  'foci_preferred':
      foci ??
      [
        {
          'type': 'livekit',
          'livekit_alias': '!room:example.org',
          'livekit_service_url': 'https://matrix.example.org/livekit-jwt-service',
        },
      ],
  'focus_active': {'type': 'livekit', 'focus_selection': 'oldest_membership'},
};

void main() {
  group('MatrixRtcMembership.fromContent', () {
    test('parses a real Element Call membership', () {
      final membership = MatrixRtcMembership.fromContent(
        content: contentFixture(),
        userId: '@alice:example.org',
      )!;

      expect(membership.userId, '@alice:example.org');
      expect(membership.deviceId, 'YERAQSHKJW');
      expect(membership.application, 'm.call');
      expect(membership.isCall, isTrue);
      expect(membership.intent, 'audio');
      expect(membership.isExpired, isFalse);
      expect(membership.focusPreferred.single.serviceUrl,
          'https://matrix.example.org/livekit-jwt-service');
    });

    // Leaving a call is an empty state event, not a redaction. Getting this
    // wrong would show everyone who has *ever* been in a call as still present.
    test('empty content means the person left', () {
      expect(
        MatrixRtcMembership.fromContent(
          content: const {},
          userId: '@alice:example.org',
        ),
        isNull,
      );
    });

    test('a membership past created_ts + expires is expired', () {
      final old = DateTime.now()
          .subtract(const Duration(hours: 5))
          .millisecondsSinceEpoch;
      final membership = MatrixRtcMembership.fromContent(
        content: contentFixture(createdTs: old, expires: 14400000),
        userId: '@alice:example.org',
      )!;

      expect(membership.isExpired, isTrue);
    });

    // These events come from several client implementations and versions, so a
    // malformed one must degrade rather than throw and take out the room list.
    test('missing device_id is rejected rather than throwing', () {
      final content = contentFixture()..remove('device_id');
      expect(
        MatrixRtcMembership.fromContent(
          content: content,
          userId: '@alice:example.org',
        ),
        isNull,
      );
    });

    // Current Element sets this to a random UUID, older clients to
    // "userId:deviceId". It must be carried through opaquely: parsing it as an
    // identity silently breaks key exchange against every current client.
    test('membershipID is kept verbatim, whatever shape it has', () {
      final uuid = MatrixRtcMembership.fromContent(
        content: contentFixture()
          ..['membershipID'] = 'c4dbf569-8eec-496f-a0b3-a8475aecee33',
        userId: '@alice:example.org',
      )!;
      expect(uuid.membershipId, 'c4dbf569-8eec-496f-a0b3-a8475aecee33');

      final legacy = MatrixRtcMembership.fromContent(
        content: contentFixture(),
        userId: '@alice:example.org',
      )!;
      expect(legacy.membershipId, '@alice:example.org:YERAQSHKJW');
    });

    test('a missing membershipID is empty, not an error', () {
      final content = contentFixture()..remove('membershipID');
      final membership = MatrixRtcMembership.fromContent(
        content: content,
        userId: '@alice:example.org',
      )!;
      expect(membership.membershipId, isEmpty);
    });

    test('a non-livekit focus is ignored, not fatal', () {
      final membership = MatrixRtcMembership.fromContent(
        content: contentFixture(
          foci: [
            {'type': 'something_else'},
            'not even a map',
          ],
        ),
        userId: '@alice:example.org',
      )!;

      expect(membership.focusPreferred, isEmpty);
    });

    test('missing created_ts is treated as now, not as expired', () {
      final content = contentFixture()..remove('created_ts');
      final membership = MatrixRtcMembership.fromContent(
        content: content,
        userId: '@alice:example.org',
      )!;

      expect(membership.isExpired, isFalse);
    });
  });

  group('state keys', () {
    test('builds the MSC3757 per-device key', () {
      expect(
        MatrixRtcMembership.stateKeyFor(
          userId: '@alice:example.org',
          deviceId: 'YERAQSHKJW',
        ),
        '_@alice:example.org_YERAQSHKJW_m.call',
      );
    });

    test('round-trips the user id back out', () {
      const key = '_@alice:example.org_YERAQSHKJW_m.call';
      expect(MatrixRtcMembership.userIdFromStateKey(key), '@alice:example.org');
    });

    test('rejects keys that are not per-device user keys', () {
      expect(MatrixRtcMembership.userIdFromStateKey(''), isNull);
      expect(MatrixRtcMembership.userIdFromStateKey('@alice:example.org'), isNull);
      expect(MatrixRtcMembership.userIdFromStateKey('_nonsense'), isNull);
    });
  });
}

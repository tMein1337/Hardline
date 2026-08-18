// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/matrix_rtc_membership.dart';
import 'package:hardline/features/voice/stale_membership_sweeper.dart';

const _ownUser = '@alice:example.org';
const _ownDevice = 'YERAQSHKJW';

MatrixRtcMembership membership({
  String userId = _ownUser,
  String deviceId = _ownDevice,
}) => MatrixRtcMembership.fromContent(
  content: {
    'application': 'm.call',
    'call_id': '',
    'scope': 'm.room',
    'device_id': deviceId,
    'membershipID': '$userId:$deviceId',
    'created_ts': DateTime.now().millisecondsSinceEpoch,
    'expires': kDefaultMembershipLifetime.inMilliseconds,
    'm.call.intent': 'audio',
  },
  userId: userId,
)!;

bool isStale(List<MatrixRtcMembership> live, {bool inCallHere = false}) =>
    ownMembershipIsStale(
      live: live,
      ownUserId: _ownUser,
      ownDeviceId: _ownDevice,
      inCallHere: inCallHere,
    );

void main() {
  group('ownMembershipIsStale', () {
    // The case this exists for: killed mid-call, so the membership we published
    // is still standing while we are demonstrably not in the call.
    test('our own device, no call running, is stale', () {
      expect(isStale([membership()]), isTrue);
    });

    test('a room with nothing in the call is not stale', () {
      expect(isStale(const []), isFalse);
    });

    // The guard that stops this hanging up a call in progress. `join()`
    // publishes the membership before the status reaches connected, so there is
    // a real window where our membership is live and correct.
    test('our own device is not stale while we are in the call', () {
      expect(isStale([membership()], inCallHere: true), isFalse);
    });

    test('somebody else being in the call is not our problem', () {
      expect(isStale([membership(userId: '@bob:example.org')]), isFalse);
    });

    // MSC3757 per-device state keys exist so one user can hold several
    // memberships. Clearing another device's would hang up a call happening on
    // a different machine.
    test('another device of ours is left alone', () {
      expect(isStale([membership(deviceId: 'OTHERDEVICE')]), isFalse);
    });

    test('finds ours among other participants', () {
      expect(
        isStale([
          membership(userId: '@bob:example.org', deviceId: 'BOBDEVICE'),
          membership(deviceId: 'OTHERDEVICE'),
          membership(),
        ]),
        isTrue,
      );
    });
  });
}

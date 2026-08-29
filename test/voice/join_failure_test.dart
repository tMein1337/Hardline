// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/join_failure.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart' as lk;

void main() {
  group('describeJoinFailure', () {
    // The distinction the whole file exists for. Both of these are
    // `LiveKitException`, both mean "the call did not start", and they point at
    // completely different things: one says the server was never reached, the
    // other says it answered and then no audio could get through.
    test('a media failure is not reported as an unreachable server', () {
      final media = describeJoinFailure(
        lk.MediaConnectException('Timed out waiting for PeerConnection'),
      );
      final signal = describeJoinFailure(
        lk.ConnectException(
          'refused',
          reason: lk.ConnectionErrorReason.InternalError,
        ),
      );

      expect(media, isNot(signal));
      expect(media.message, isNot(contains('unreachable')));
      expect(media.detail, contains('answered'));
      expect(signal.detail, contains('did not accept'));
    });

    test('a media failure points at the network path, not at the call', () {
      final failure = describeJoinFailure(
        lk.MediaConnectException('ice connectivity'),
      );

      expect(failure.detail.toLowerCase(), contains('firewall'));
    });

    // Reaching the homeserver at all comes before any of LiveKit, so saying so
    // rules out three systems at once.
    test('a socket failure is attributed before LiveKit', () {
      final failure = describeJoinFailure(
        const SocketException('semaphore timeout'),
      );

      expect(failure.detail, contains('never contacted'));
    });

    test('an http client failure is treated the same way', () {
      expect(
        describeJoinFailure(http.ClientException('broken pipe')),
        describeJoinFailure(const SocketException('broken pipe')),
      );
    });

    test('a timeout is distinguished from a refusal', () {
      expect(
        describeJoinFailure(lk.TimeoutException()),
        isNot(
          describeJoinFailure(
            lk.ConnectException(
              'refused',
              reason: lk.ConnectionErrorReason.InternalError,
            ),
          ),
        ),
      );
    });

    // The general LiveKit case must not swallow the two specific ones, which
    // are both subclasses of it.
    test('the general LiveKit case does not shadow the specific ones', () {
      final general = describeJoinFailure(lk.NegotiationError('nope'));

      expect(general.message, 'Call server refused');
      expect(
        general,
        isNot(describeJoinFailure(lk.MediaConnectException('x'))),
      );
      expect(
        general,
        isNot(
          describeJoinFailure(
            lk.ConnectException(
              'refused',
              reason: lk.ConnectionErrorReason.InternalError,
            ),
          ),
        ),
      );
    });

    test('anything unrecognised still yields something showable', () {
      final failure = describeJoinFailure(StateError('who knows'));

      expect(failure.message, isNotEmpty);
      expect(failure.detail, isNotEmpty);
    });

    // The call bar clips to one line in a narrow sidebar, so a message that
    // does not fit is a message nobody reads.
    test('every message is short enough for the call bar', () {
      final errors = <Object>[
        lk.MediaConnectException('x'),
        lk.ConnectException(
          'refused',
          reason: lk.ConnectionErrorReason.InternalError,
        ),
        lk.TimeoutException(),
        lk.NegotiationError('x'),
        const SocketException('x'),
        http.ClientException('x'),
        StateError('x'),
      ];

      for (final error in errors) {
        final failure = describeJoinFailure(error);
        expect(
          failure.message.length,
          lessThanOrEqualTo(28),
          reason: '"${failure.message}" will be ellipsised in the call bar',
        );
        // The detail is the half that is allowed to explain itself.
        expect(failure.detail.length, greaterThan(failure.message.length));
      }
    });
  });
}

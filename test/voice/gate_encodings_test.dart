// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:hardline/features/voice/gate_encodings.dart';

void main() {
  group('gateEncodings', () {
    // The bug this whole helper exists for. A Windows audio sender reports its
    // parameters with no encodings, the old code looped over that empty list,
    // set nothing, and handed the object back — and because the native side
    // zips the incoming list against its own and stops when the incoming one
    // runs out, nothing was applied and nothing failed. The gate reported the
    // microphone shut while it transmitted.
    test('synthesises an encoding when the sender reports none', () {
      final params = rtc.RTCRtpParameters(encodings: []);
      final closed = gateEncodings(params, open: false);

      expect(closed, hasLength(1));
      expect(closed.single.active, isFalse);
    });

    test('synthesises an encoding when encodings is null', () {
      final params = rtc.RTCRtpParameters();
      final open = gateEncodings(params, open: true);

      expect(open, hasLength(1));
      expect(open.single.active, isTrue);
    });

    test('one encoding per encoding a sender reports', () {
      final params = rtc.RTCRtpParameters(
        encodings: [
          rtc.RTCRtpEncoding(rid: 'a'),
          rtc.RTCRtpEncoding(rid: 'b'),
        ],
      );

      final closed = gateEncodings(params, open: false);
      expect(closed, hasLength(2));
      expect(closed.every((e) => e.active == false), isTrue);

      final reopened = gateEncodings(params, open: true);
      expect(reopened, hasLength(2));
      expect(reopened.every((e) => e.active == true), isTrue);
    });

    // The other half of the bug. The cached encodings carry fields a sender
    // will not take back — ssrc 0, maxBitrate 0, a video-only scale factor —
    // and once flutter_webrtc 1.6.3 started applying them, WebRTC refused the
    // whole change. Only `active` and the `rid` that says which encoding are
    // sent; the native side leaves every other field as the publisher set it.
    test('sends nothing but active and rid', () {
      final params = rtc.RTCRtpParameters(
        encodings: [
          rtc.RTCRtpEncoding(
            rid: 'high',
            maxBitrate: 0,
            ssrc: 0,
            scaleResolutionDownBy: 1.0,
          ),
        ],
      );

      final encoding = gateEncodings(params, open: false).single;
      expect(encoding.active, isFalse);
      expect(encoding.rid, 'high');
      expect(encoding.maxBitrate, isNull);
      expect(encoding.ssrc, isNull);
      expect(encoding.scaleResolutionDownBy, isNull);
      expect(encoding.numTemporalLayers, isNull);
    });

    test('the map sent carries only active, rid and priority', () {
      final params = rtc.RTCRtpParameters(
        encodings: [rtc.RTCRtpEncoding(rid: 'a', maxBitrate: 0)],
      );
      params.encodings = gateEncodings(params, open: false);
      final sent = (params.toMap()['encodings'] as List).single as Map;
      expect(sent.keys.toSet(), {'active', 'rid', 'priority'});
    });

    test('keeps the priority the sender had', () {
      final params = rtc.RTCRtpParameters(
        encodings: [rtc.RTCRtpEncoding(priority: rtc.RTCPriorityType.high)],
      );
      expect(
        gateEncodings(params, open: false).single.priority,
        rtc.RTCPriorityType.high,
      );
    });

    // A fresh list, so the gate never edits the sender's cached parameters
    // in place — a closed gate used to leave `active: false` sitting in them.
    test('does not modify the encodings it was given', () {
      final original = rtc.RTCRtpEncoding(rid: 'a', active: true);
      final params = rtc.RTCRtpParameters(encodings: [original]);

      gateEncodings(params, open: false);
      expect(original.active, isTrue);
    });
    test('round trips closed and open again', () {
      final params = rtc.RTCRtpParameters(encodings: [rtc.RTCRtpEncoding()]);

      expect(gateEncodings(params, open: false).single.active, isFalse);
      expect(gateEncodings(params, open: true).single.active, isTrue);
      expect(gateEncodings(params, open: false).single.active, isFalse);
    });

    // The result is what gets assigned back onto `parameters.encodings` and
    // serialised by `toMap()`, so it has to survive that trip with `active`
    // intact — that map is the only thing the native side ever sees.
    test('survives the toMap the platform channel actually sends', () {
      final params = rtc.RTCRtpParameters(encodings: []);
      params.encodings = gateEncodings(params, open: false);

      final sent = params.toMap()['encodings'] as List<dynamic>;
      expect(sent, hasLength(1));
      expect((sent.single as Map)['active'], isFalse);
    });
  });
}

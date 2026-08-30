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

    test('flips active on the encodings a sender does report', () {
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

    // Everything else about an encoding — the rid, the bitrate ceiling, the
    // simulcast scaling — belongs to whoever published the track. A gate that
    // rebuilt them from scratch would silently drop a sender's configuration
    // every time somebody stopped talking.
    test('preserves everything other than active', () {
      final params = rtc.RTCRtpParameters(
        encodings: [
          rtc.RTCRtpEncoding(rid: 'high', maxBitrate: 96000, ssrc: 42),
        ],
      );

      final encoding = gateEncodings(params, open: false).single;
      expect(encoding.rid, 'high');
      expect(encoding.maxBitrate, 96000);
      expect(encoding.ssrc, 42);
      expect(encoding.active, isFalse);
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

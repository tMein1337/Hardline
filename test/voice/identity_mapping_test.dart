// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/livekit_call_controller.dart';

void main() {
  group('matrixUserIdOf', () {
    // The whole point: a Matrix id already contains a colon, so splitting on
    // the first one yields "@bob" and every per-user volume lands on the wrong
    // person — or on nobody.
    test('splits on the last colon, not the first', () {
      expect(
        matrixUserIdOf('@alice:example.org:LQTQHXJKCZ'),
        '@alice:example.org',
      );
    });

    test('handles a server name with a port', () {
      expect(
        matrixUserIdOf('@bob:example.org:8448:DEVICEID'),
        '@bob:example.org:8448',
      );
    });

    // A participant from a client that builds identities differently must not
    // disappear from the roster; falling back to the raw value keeps them
    // addressable, just under an unusual key.
    test('falls back to the raw identity when it is not one of ours', () {
      expect(matrixUserIdOf('some-opaque-identity'), 'some-opaque-identity');
      expect(matrixUserIdOf(''), '');
    });

    test('leaves a bare matrix id alone rather than truncating it', () {
      expect(matrixUserIdOf('@bob:example.org'), '@bob:example.org');
    });
  });
}

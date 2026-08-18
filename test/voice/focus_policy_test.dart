// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/focus_policy.dart';
import 'package:hardline/features/voice/matrix_rtc_membership.dart';

/// The focus URL decides where an OpenID token for our own account is sent,
/// and it comes from a state event any room member can write. Every rejection
/// below is therefore a real message somebody can send, not a malformed value.
LiveKitFocus _focus(String url) =>
    LiveKitFocus(serviceUrl: url, alias: '!room:example.org');

void main() {
  group('isAcceptableFocusUrl', () {
    test('https is accepted', () {
      expect(isAcceptableFocusUrl('https://matrix.example.org'), isTrue);
      expect(
        isAcceptableFocusUrl('https://matrix.example.org/livekit-jwt-service'),
        isTrue,
      );
      expect(isAcceptableFocusUrl('https://example.org:8448/sfu'), isTrue);
    });

    // An OpenID token in cleartext is the whole risk, realised.
    test('plain http to a remote host is refused', () {
      expect(isAcceptableFocusUrl('http://evil.example'), isFalse);
      expect(isAcceptableFocusUrl('http://matrix.example.org/jwt'), isFalse);
    });

    test('http to loopback is allowed, for local development', () {
      expect(isAcceptableFocusUrl('http://localhost:8080'), isTrue);
      expect(isAcceptableFocusUrl('http://127.0.0.1:8080/sfu'), isTrue);
      expect(isAcceptableFocusUrl('http://[::1]:8080'), isTrue);
    });

    test('a host that merely looks like loopback is not', () {
      expect(isAcceptableFocusUrl('http://localhost.evil.example'), isFalse);
      expect(isAcceptableFocusUrl('http://127.0.0.1.evil.example'), isFalse);
    });

    test('credentials in the URL are refused', () {
      expect(
        isAcceptableFocusUrl('https://user:pass@evil.example/sfu'),
        isFalse,
      );
    });

    test('a query or fragment is refused', () {
      expect(isAcceptableFocusUrl('https://example.org/sfu?a=b'), isFalse);
      expect(isAcceptableFocusUrl('https://example.org/sfu#x'), isFalse);
    });

    test('non-network schemes are refused', () {
      for (final url in [
        'file:///C:/Windows/System32',
        'javascript:alert(1)',
        'data:text/plain,hello',
        'ftp://example.org',
        'ws://example.org',
      ]) {
        expect(isAcceptableFocusUrl(url), isFalse, reason: url);
      }
    });

    test('relative, empty and nonsense values are refused', () {
      for (final url in ['', '   ', '/sfu', 'example.org', 'https://', '::::']) {
        expect(isAcceptableFocusUrl(url), isFalse, reason: '"$url"');
      }
    });
  });

  group('chooseFocus', () {
    final ours = _focus('https://matrix.example.org/livekit-jwt-service');
    final theirs = _focus('https://sfu.other.example/livekit-jwt-service');
    final hostile = _focus('http://evil.example/collect');

    test('an advertised focus on our own homeserver wins', () {
      final chosen = chooseFocus(
        advertised: [theirs, ours],
        homeserverOrigin: 'https://matrix.example.org',
        fallback: null,
      );
      expect(chosen, ours);
    });

    // Refusing a third-party focus would not make the call safer, it would put
    // us alone in a parallel call. It has to be usable, just not cleartext.
    test('a third-party https focus is used when it is the only one', () {
      final chosen = chooseFocus(
        advertised: [theirs],
        homeserverOrigin: 'https://matrix.example.org',
        fallback: null,
      );
      expect(chosen, theirs);
    });

    test('an unacceptable focus is skipped in favour of a usable one', () {
      final chosen = chooseFocus(
        advertised: [hostile, theirs],
        homeserverOrigin: 'https://matrix.example.org',
        fallback: null,
      );
      expect(chosen, theirs);
    });

    test('a room advertising only cleartext falls back', () {
      final chosen = chooseFocus(
        advertised: [hostile],
        homeserverOrigin: 'https://matrix.example.org',
        fallback: ours,
      );
      expect(chosen, ours);
    });

    test('nothing usable and no fallback means no call, not any host', () {
      final chosen = chooseFocus(
        advertised: [hostile],
        homeserverOrigin: 'https://matrix.example.org',
        fallback: null,
      );
      expect(chosen, isNull);
    });

    test('the fallback is held to the same standard', () {
      final chosen = chooseFocus(
        advertised: const [],
        homeserverOrigin: 'http://matrix.example.org',
        fallback: _focus('http://matrix.example.org/livekit-jwt-service'),
      );
      expect(chosen, isNull);
    });

    test('an empty room uses the fallback', () {
      final chosen = chooseFocus(
        advertised: const [],
        homeserverOrigin: 'https://matrix.example.org',
        fallback: ours,
      );
      expect(chosen, ours);
    });
  });

  group('focusOrigin', () {
    test('reduces a URL to scheme, host and port', () {
      expect(
        focusOrigin('https://matrix.example.org/livekit-jwt-service'),
        'https://matrix.example.org',
      );
      expect(
        focusOrigin('https://matrix.example.org:8448/sfu'),
        'https://matrix.example.org:8448',
      );
    });

    test('is null for anything without an origin', () {
      expect(focusOrigin('/sfu'), isNull);
      expect(focusOrigin('not a url at all'), isNull);
    });
  });
}

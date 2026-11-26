// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/voice/wayland_screencast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('hardline/screencast');
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'a started share wraps the registered track as a local stream',
    () async {
      answer(
        (_) => {
          'sessionId': 'portal:1',
          'streamId': 'stream-a',
          'trackId': 'track-a',
        },
      );

      final share = await WaylandScreencast.start();

      expect(share, isNotNull);
      expect(share!.sessionId, 'portal:1');
      expect(share.stream.id, 'stream-a');
      expect(share.stream.getAudioTracks(), isEmpty);
      final video = share.stream.getVideoTracks().single;
      expect(video.id, 'track-a');
      expect(video.kind, 'video');
    },
  );

  test('a cancelled picker is null, not an error', () async {
    answer((_) => null);
    expect(await WaylandScreencast.start(), isNull);
  });

  test('stop reaches the native side only for portal shares', () async {
    answer((_) => null);

    // A flutter_webrtc capture source id, as on Windows or X11.
    await WaylandScreencast.stop('0:12345');
    expect(calls, isEmpty);

    await WaylandScreencast.stop('portal:3');
    expect(calls.single.method, 'stop');
    expect(calls.single.arguments, {'sessionId': 'portal:3'});
  });

  test('a build without the channel reports sharing unavailable', () async {
    // No handler at all: MissingPluginException, as on Windows and macOS.
    expect(await WaylandScreencast.isAvailable(), isFalse);
  });
}

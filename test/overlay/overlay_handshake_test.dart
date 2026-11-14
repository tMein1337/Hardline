// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/overlay/overlay_app.dart';
import 'package:hardline/features/overlay/overlay_channel.dart';
import 'package:hardline/features/overlay/overlay_controller.dart';
import 'package:hardline/features/overlay/overlay_layout.dart';
import 'package:hardline/features/overlay/overlay_prefs_state.dart';
import 'package:hardline/features/overlay/overlay_wire.dart';
import 'package:hardline/features/voice/live_participant.dart';
import 'package:hardline/features/voice/speaking_participants.dart';

// The overlay did not appear on the first call after launch, and did on every
// call after it. `show` creates the overlay's engine; the snapshot handed to
// it and the speaking update sent straight afterwards both arrived before the
// engine's Dart was listening; a channel with no listener keeps one message,
// so the second pushed out the first. The HUD came up knowing who was
// speaking and not who was in the call.
//
// Two halves fix it and each is tested here on its own: the app no longer
// treats a window as evidence of a HUD, and the overlay listens from its first
// line and says what it has done. `integration_test/overlay_window_flow.dart`
// runs the two against each other, in a real second engine.

/// A window that does only what it is told, and says nothing back on its own.
class _SilentChannel extends OverlayChannel {
  final opacities = <int>[];
  final pushed = <String>[];
  final shownWith = <String>[];
  bool shown = false;

  final _events = StreamController<String>.broadcast(sync: true);

  /// The overlay isolate speaking.
  void say(String payload) => _events.add(payload);

  @override
  Stream<String> get edits => _events.stream;

  @override
  Future<bool> show({
    required String monitorId,
    required bool clickThrough,
    required bool excludeFromCapture,
    required int opacity,
    required String state,
  }) async {
    shown = true;
    opacities.add(opacity);
    shownWith.add(state);
    return true;
  }

  @override
  Future<void> hide() async => shown = false;

  @override
  Future<void> setOpacity(int alpha) async => opacities.add(alpha);

  @override
  Future<void> setClickThrough(bool value) async {}

  @override
  Future<void> pushState(String state) async => pushed.add(state);
}

LiveParticipant _person(String id) => LiveParticipant(
  userId: id,
  identity: id,
  deviceId: 'D',
  displayName: id,
  avatarMxc: null,
  isLocal: false,
  micMuted: false,
  feeds: const [],
);

const _alice = '@alice:example.org';
const _talking = SpeakingParticipants(
  roomId: '!r:example.org',
  userIds: {_alice},
);

const _palette = OverlayPalette(
  speakingRing: 0xFFFF7A18,
  text: 0xFFFFFFFF,
  plate: 0xFF08080A,
);

OverlaySnapshot _snapshot(List<String> names) => OverlaySnapshot(
  people: [
    for (final name in names)
      OverlayPerson(userId: '@$name:example.org', name: name, avatar: null),
  ],
  layout: const OverlayLayout(id: kDefaultOverlayLayoutId, name: 'Default'),
  palette: _palette,
  editing: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Off Windows the controller never reaches the channel; see the same guard
  // in `overlay_linger_test.dart`.
  final onWindows = OverlayChannel.isSupported;

  group('the app does not take a window for a HUD', () {
    late _SilentChannel channel;
    late OverlayController controller;

    Future<void> join({
      Duration linger = const Duration(milliseconds: 80),
      double idleOpacity = 0.4,
    }) async {
      await controller.setPrefs(
        OverlayPrefsState(
          enabled: true,
          linger: linger,
          layouts: [
            OverlayLayout(
              id: kDefaultOverlayLayoutId,
              name: 'Default',
              idleOpacity: idleOpacity,
            ),
          ],
        ),
      );
      await controller.setParticipants(
        inCall: true,
        participants: [_person(_alice)],
      );
    }

    int shownSerial() => overlaySerialOf(channel.shownWith.last);

    setUp(() {
      channel = _SilentChannel();
      controller = OverlayController(
        channel: channel,
        persistLayout: (_) {},
        fetchAvatar: (_, _) async => Uint8List(0),
      );
    });

    tearDown(() => controller.dispose());

    test('the window comes up invisible', () async {
      await join();
      expect(channel.shown, isTrue);
      expect(channel.opacities, [0]);
    }, skip: !onWindows);

    // The whole of the rule. An engine that failed to start, or has not yet
    // been told who is in the call, leaves a window with nothing worth seeing
    // in it — and in one case an opaque sheet over the monitor.
    test('and stays invisible until the overlay says it has drawn', () async {
      await join();

      // Everything that used to raise it.
      controller.setSpeaking(_talking);
      controller.refreshOpacity();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(channel.opacities.toSet(), {0});

      channel.say(OverlayDrawn(shownSerial()).encode());
      expect(channel.opacities.last, 255);
    }, skip: !onWindows);

    // A frame confirmed late from the call before. Raising the window for it
    // is exactly the flash of the previous roster this exists to prevent.
    test('a draw from before this show does not count', () async {
      await join();
      final first = shownSerial();
      channel.say(OverlayDrawn(first).encode());

      await controller.setParticipants(inCall: false, participants: const []);
      await join();
      expect(shownSerial(), greaterThan(first));
      channel.opacities.clear();

      channel.say(OverlayDrawn(first).encode());
      expect(channel.opacities, isEmpty);

      channel.say(OverlayDrawn(shownSerial()).encode());
      expect(channel.opacities.last, 255);
    }, skip: !onWindows);

    // The ready message sends the state again under a new serial. Whichever
    // of the two the overlay confirms, it has drawn this call's roster.
    test('a draw of a later sending counts', () async {
      await join();
      channel.say(OverlayDrawn(shownSerial() + 1).encode());
      expect(channel.opacities.last, 255);
    }, skip: !onWindows);

    // The engine's start-up is not the HUD's time on screen. Started at
    // `show`, a slow first launch ate the linger and the roster went straight
    // from invisible to faded.
    test('the linger runs from the reveal, not from the show', () async {
      await join(linger: const Duration(milliseconds: 120));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      channel.say(OverlayDrawn(shownSerial()).encode());
      expect(channel.opacities.last, 255);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(channel.opacities.last, 255, reason: 'still inside the linger');

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(channel.opacities.last, 102, reason: '0.4 * 255, after it');
    }, skip: !onWindows);

    test('edit mode is revealed at full whatever the settings say', () async {
      await controller.setPrefs(
        const OverlayPrefsState(
          enabled: true,
          layouts: [
            OverlayLayout(
              id: kDefaultOverlayLayoutId,
              name: 'Default',
              activeOpacity: 0.2,
              idleOpacity: 0,
            ),
          ],
        ),
      );
      controller.setEditing(true);
      // Not awaitable: the chord that calls this does not wait either.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(channel.opacities, [0]);

      channel.say(OverlayDrawn(shownSerial()).encode());
      expect(channel.opacities.last, 255);
    }, skip: !onWindows);

    group('when the overlay announces itself', () {
      // Whatever was pushed before this may never have arrived, and there is
      // no way to ask. So everything goes again, roster first: the overlay
      // draws a ring around somebody it has been told about.
      test('it is sent the roster and then who is speaking', () async {
        controller.setSpeaking(_talking);
        await join();
        channel.pushed.clear();

        channel.say(const OverlayReady().encode());
        await Future<void>.delayed(Duration.zero);

        expect(channel.pushed, hasLength(2));
        expect(decodeOverlayMessage(channel.pushed[0]), isA<OverlaySnapshot>());
        expect(
          decodeOverlayMessage(channel.pushed[1]),
          const OverlaySpeaking({_alice}),
        );
      }, skip: !onWindows);

      test('the roster goes under a new serial', () async {
        await join();
        final shown = shownSerial();

        channel.say(const OverlayReady().encode());
        await Future<void>.delayed(Duration.zero);

        expect(overlaySerialOf(channel.pushed.last), greaterThan(shown));
      }, skip: !onWindows);

      test('nothing is sent while nothing is shown', () async {
        channel.say(const OverlayReady().encode());
        await Future<void>.delayed(Duration.zero);
        expect(channel.pushed, isEmpty);
        expect(channel.shown, isFalse);
      }, skip: !onWindows);
    });

    test('a dragged layout still comes back over the same wire', () async {
      OverlayLayout? persisted;
      final dragging = OverlayController(
        channel: channel,
        persistLayout: (layout) => persisted = layout,
        fetchAvatar: (_, _) async => null,
      );
      addTearDown(dragging.dispose);

      channel.say(
        const OverlayEdit(
          OverlayLayout(id: 'ignored', name: 'ignored', x: 0.5, y: 0.25),
        ).encode(),
      );

      expect(persisted?.x, 0.5);
      expect(persisted?.y, 0.25);
      // Only the position comes back; the id is the active layout's.
      expect(persisted?.id, kDefaultOverlayLayoutId);
    });
  });

  group('the overlay says what it has done', () {
    late List<Object?> said;

    OverlayModel model() =>
        OverlayModel(send: (payload) async => said.add(payload));

    List<Object?> decoded() => [
      for (final payload in said) decodeOverlayMessage(payload as String?),
    ];

    setUp(() => said = []);

    test('it announces itself', () {
      model().announce();
      expect(decoded().single, isA<OverlayReady>());
    });

    testWidgets('a snapshot is confirmed once its frame is finished', (
      tester,
    ) async {
      final overlay = model();
      await tester.pumpWidget(OverlayRoot(model: overlay));

      overlay.receive(_snapshot(['Alice']).encode(serial: 7));
      // Having the data is not having drawn it.
      expect(said, isEmpty);

      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect((decoded().single! as OverlayDrawn).serial, 7);

      // And only once.
      await tester.pump();
      expect(said, hasLength(1));
    });

    // The app's second sending after `ready` is the same roster. Nothing is
    // dirtied by it, so no frame would happen on its own — and the app would
    // wait for ever for a confirmation of the serial it is watching for.
    testWidgets('an identical snapshot is still confirmed', (tester) async {
      final overlay = model();
      await tester.pumpWidget(OverlayRoot(model: overlay));

      overlay.receive(_snapshot(['Alice']).encode(serial: 1));
      await tester.pump();
      overlay.receive(_snapshot(['Alice']).encode(serial: 2));
      await tester.pump();

      expect(
        [for (final message in decoded()) (message! as OverlayDrawn).serial],
        [1, 2],
      );
    });

    testWidgets('who is speaking is not a snapshot and confirms nothing', (
      tester,
    ) async {
      final overlay = model();
      await tester.pumpWidget(OverlayRoot(model: overlay));

      overlay.receive(const OverlaySpeaking({_alice}).encode());
      await tester.pump();

      expect(said, isEmpty);
    });

    testWidgets('a failing send does not take the overlay down', (
      tester,
    ) async {
      final overlay = OverlayModel(
        send: (_) async => throw MissingPluginException('no runner'),
      );
      await tester.pumpWidget(OverlayRoot(model: overlay));

      overlay.announce();
      overlay.receive(_snapshot(['Alice']).encode(serial: 1));
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // The defect itself, at the channel. Both messages are delivered the way the
  // engine delivers them to an isolate that has only just started: after
  // `overlayMain` has returned and before the first frame has been built.
  group('messages that arrive before the first frame', () {
    const channelName = 'hardline/overlay_state';
    const codec = StandardMethodCodec();

    Future<void> deliver(WidgetTester tester, String payload) =>
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channelName,
          codec.encodeMethodCall(MethodCall('state', payload)),
          (_) {},
        );

    testWidgets('are both kept, roster and speaker', (tester) async {
      final said = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(channelName),
        (call) async {
          said.add(call.arguments as String);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(channelName),
          null,
        ),
      );

      runOverlayApp();
      // What `show` carries, and what follows it a moment later. With the
      // handler installed from a widget's `initState` the second of these
      // pushed the first out of a one-message buffer.
      await deliver(tester, _snapshot(['Alice', 'Bob']).encode(serial: 1));
      await deliver(tester, const OverlaySpeaking({_alice}).encode());

      await tester.pump();
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);

      final messages = [
        for (final payload in said) decodeOverlayMessage(payload),
      ];
      expect(messages.first, isA<OverlayReady>(), reason: 'said before runApp');
      expect(messages.whereType<OverlayDrawn>().map((drawn) => drawn.serial), [
        1,
      ]);
    });
  });

  group('the wire', () {
    test('ready and drawn survive the round trip', () {
      expect(
        decodeOverlayMessage(const OverlayReady().encode()),
        isA<OverlayReady>(),
      );
      final drawn = decodeOverlayMessage(const OverlayDrawn(42).encode());
      expect((drawn! as OverlayDrawn).serial, 42);
    });

    // The serial is on the envelope so that two sendings of one roster are
    // still the same roster — which is what lets an unchanged one be skipped.
    test('a serial does not make two equal snapshots differ', () {
      final snapshot = _snapshot(['Alice']);
      final first = decodeOverlayMessage(snapshot.encode(serial: 1));
      final second = decodeOverlayMessage(snapshot.encode(serial: 2));

      expect(first, second);
      expect(overlaySerialOf(snapshot.encode(serial: 2)), 2);
    });

    test('a payload with no serial reads as zero', () {
      expect(overlaySerialOf(null), 0);
      expect(overlaySerialOf('not json'), 0);
      expect(overlaySerialOf('{"kind":"snapshot"}'), 0);
      expect(overlaySerialOf(const OverlaySpeaking({}).encode()), 0);
    });
  });
}

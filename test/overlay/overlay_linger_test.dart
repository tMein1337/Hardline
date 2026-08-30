// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/overlay/overlay_channel.dart';
import 'package:hardline/features/overlay/overlay_controller.dart';
import 'package:hardline/features/overlay/overlay_layout.dart';
import 'package:hardline/features/overlay/overlay_prefs_state.dart';
import 'package:hardline/features/voice/live_participant.dart';
import 'package:hardline/features/voice/speaking_participants.dart';

/// Records what the controller asks the window to do.
///
/// Subclasses the real channel rather than mocking an interface, which is the
/// idiom the rest of this suite uses. Every method channel call underneath is
/// a no-op off Windows, so nothing here reaches a platform.
class _FakeChannel extends OverlayChannel {
  final opacities = <int>[];
  bool shown = false;

  @override
  Future<bool> show({
    required String monitorId,
    required bool clickThrough,
    required bool excludeFromCapture,
    required String state,
  }) async {
    shown = true;
    return true;
  }

  @override
  Future<void> hide() async => shown = false;

  @override
  Future<void> setOpacity(int alpha) async => opacities.add(alpha);

  @override
  Future<void> setClickThrough(bool value) async {}

  int pushes = 0;

  @override
  Future<void> pushState(String state) async => pushes++;
}

LiveParticipant _personWithAvatar(String id) => LiveParticipant(
  userId: id,
  identity: id,
  deviceId: 'D',
  displayName: id,
  avatarMxc: 'mxc://example.org/abc',
  isLocal: false,
  micMuted: false,
  feeds: const [],
);

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

void main() {
  // `OverlayChannel`'s constructor installs a method-call handler, which needs
  // a binding. It is a real channel underneath the fake.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChannel channel;
  late OverlayController controller;

  /// An enabled overlay with a known linger and idle opacity.
  Future<void> arrange({
    Duration linger = const Duration(seconds: 2),
    double idleOpacity = 0,
    double activeOpacity = 1,
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
            activeOpacity: activeOpacity,
          ),
        ],
      ),
    );
    await controller.setParticipants(
      inCall: true,
      participants: [_person('@a:example.org')],
    );
  }

  setUp(() {
    channel = _FakeChannel();
    controller = OverlayController(
      channel: channel,
      persistLayout: (_) {},
      fetchAvatar: (_, _) async => Uint8List(0),
    );
  });

  tearDown(() => controller.dispose());

  // Off Windows `OverlayChannel.isSupported` is false and the controller does
  // nothing at all, which would make every assertion below vacuously true.
  // Skipped rather than faked: the logic under test is the timer, and a
  // controller that never reaches the channel is not exercising it.
  final onWindows = OverlayChannel.isSupported;

  test('coming up starts at full', () async {
    await arrange();
    expect(channel.opacities.first, 255);
  }, skip: !onWindows);

  // The point of the linger. Without it the roster would snap to its idle
  // opacity between two sentences, which reads as flicker rather than as a
  // fade.
  test('stays at full while somebody is still talking', () async {
    await arrange(linger: const Duration(milliseconds: 200));
    channel.opacities.clear();

    controller.setSpeaking(
      const SpeakingParticipants(
        roomId: '!r:example.org',
        userIds: {'@a:example.org'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.setSpeaking(const SpeakingParticipants.silent());
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // Talking again before the linger ran out: the drop must never have
    // happened.
    controller.setSpeaking(
      const SpeakingParticipants(
        roomId: '!r:example.org',
        userIds: {'@a:example.org'},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(channel.opacities, isNot(contains(0)));
  }, skip: !onWindows);

  test('drops to the idle opacity once the linger expires', () async {
    await arrange(linger: const Duration(milliseconds: 100), idleOpacity: 0.4);
    channel.opacities.clear();

    controller.setSpeaking(
      const SpeakingParticipants(
        roomId: '!r:example.org',
        userIds: {'@a:example.org'},
      ),
    );
    controller.setSpeaking(const SpeakingParticipants.silent());
    await Future<void>.delayed(const Duration(milliseconds: 250));

    // 0.4 * 255, rounded.
    expect(channel.opacities.last, 102);
  }, skip: !onWindows);

  test('disappears entirely when the idle opacity is zero', () async {
    await arrange(linger: const Duration(milliseconds: 100));
    channel.opacities.clear();

    controller.setSpeaking(
      const SpeakingParticipants(
        roomId: '!r:example.org',
        userIds: {'@a:example.org'},
      ),
    );
    controller.setSpeaking(const SpeakingParticipants.silent());
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(channel.opacities.last, 0);
  }, skip: !onWindows);

  test('does not repeat a value it has already sent', () async {
    await arrange(linger: const Duration(milliseconds: 50));
    channel.opacities.clear();

    for (var i = 0; i < 3; i++) {
      controller.setSpeaking(
        const SpeakingParticipants(
          roomId: '!r:example.org',
          userIds: {'@a:example.org'},
        ),
      );
      controller.setSpeaking(const SpeakingParticipants.silent());
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Whatever the sequence, no two consecutive calls carry the same value.
    for (var i = 1; i < channel.opacities.length; i++) {
      expect(channel.opacities[i], isNot(channel.opacities[i - 1]));
    }
  }, skip: !onWindows);

  group('the linger preference', () {
    test('defaults to something short but not instant', () {
      expect(const OverlayPrefsState().linger, kDefaultOverlayLinger);
      expect(kDefaultOverlayLinger, greaterThan(kMinOverlayLinger));
      expect(kDefaultOverlayLinger, lessThan(kMaxOverlayLinger));
    });

    test('round-trips through JSON', () {
      const state = OverlayPrefsState(linger: Duration(minutes: 5));
      expect(
        OverlayPrefsState.fromJson(state.toJson()).linger,
        const Duration(minutes: 5),
      );
    });

    // Clamped at parse, like the tooltip delay: a hand-edited value out of
    // range would otherwise be a HUD that never comes back, with nothing on
    // screen to explain it.
    test('clamps a stored value outside the range', () {
      expect(
        OverlayPrefsState.fromJson({'lingerMs': 999999999}).linger,
        kMaxOverlayLinger,
      );
      expect(
        OverlayPrefsState.fromJson({'lingerMs': 0}).linger,
        kMinOverlayLinger,
      );
    });

    test('falls back when the value is missing or not a number', () {
      expect(OverlayPrefsState.fromJson({}).linger, kDefaultOverlayLinger);
      expect(
        OverlayPrefsState.fromJson({'lingerMs': 'soon'}).linger,
        kDefaultOverlayLinger,
      );
    });
  });

  // The setting exists because the overlay sits over a game somebody is
  // trying to see, and "loud enough to notice" is a judgement about that game.
  group('the talking opacity', () {
    test('is what a speaker brings the HUD up to', () async {
      // Let the linger take it down to idle first. Without a transition to
      // watch there is nothing to assert: `_applyOpacity` deliberately skips a
      // value it has already sent, so speaking while already at the talking
      // opacity is correctly a no-op.
      await arrange(
        linger: const Duration(milliseconds: 50),
        activeOpacity: 0.5,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(channel.opacities.last, 0);

      controller.setSpeaking(
        const SpeakingParticipants(
          roomId: '!r:example.org',
          userIds: {'@a:example.org'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 0.5 * 255, rounded.
      expect(channel.opacities.last, 128);
    }, skip: !onWindows);

    test('applies to the first frame too, not just to later speech', () async {
      await arrange(activeOpacity: 0.5);
      // Coming up at full when the user asked for half would announce the
      // overlay with a flash of exactly the brightness they ruled out.
      expect(channel.opacities.first, 128);
    }, skip: !onWindows);

    test('can be lower than the idle opacity, strange as that is', () async {
      // "Get out of the way when the conversation picks up" is coherent, and
      // refusing it would be the app deciding it knows better about somebody
      // else's screen.
      await arrange(
        linger: const Duration(milliseconds: 50),
        activeOpacity: 0.2,
        idleOpacity: 0.8,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(channel.opacities.last, 204);

      controller.setSpeaking(
        const SpeakingParticipants(
          roomId: '!r:example.org',
          userIds: {'@a:example.org'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(channel.opacities.last, 51);
    }, skip: !onWindows);
  });

  // Two moments that change what the opacity should be without anybody
  // starting or stopping talking. Both were broken, and the first is why
  // toggling the edit chord looked like it "refreshed" the overlay.
  group('refreshOpacity', () {
    test('hands the window back to the settings after edit mode', () async {
      await arrange(
        linger: const Duration(milliseconds: 50),
        idleOpacity: 0.4,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(channel.opacities.last, 102);

      controller.setEditing(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(channel.opacities.last, 255, reason: 'edit mode pins it at full');

      controller.setEditing(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        channel.opacities.last,
        102,
        reason: 'and leaving it must give the setting back',
      );
    }, skip: !onWindows);

    // What the settings pane does when a slider is released. Handed the
    // layout directly, because the preference write only reaches the
    // controller a rebuild later — asking it to re-evaluate before then
    // computes the old value, and the new one lands whenever something else
    // happens to reconcile. That was an opacity which only took effect on
    // closing the settings screen.
    test('applyLayoutNow takes effect immediately', () async {
      await arrange(
        linger: const Duration(milliseconds: 50),
        idleOpacity: 0.4,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(channel.opacities.last, 102);

      controller.applyLayoutNow(
        const OverlayLayout(
          id: kDefaultOverlayLayoutId,
          name: 'Default',
          idleOpacity: 0.8,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(channel.opacities.last, 204);
    }, skip: !onWindows);

    test('pushes a changed setting at the window', () async {
      await arrange(
        linger: const Duration(milliseconds: 50),
        idleOpacity: 0.4,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(channel.opacities.last, 102);

      // What the settings pane does on release: store, then push.
      await controller.setPrefs(
        OverlayPrefsState(
          enabled: true,
          linger: const Duration(milliseconds: 50),
          layouts: const [
            OverlayLayout(
              id: kDefaultOverlayLayoutId,
              name: 'Default',
              idleOpacity: 0.8,
            ),
          ],
        ),
      );
      controller.refreshOpacity();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(channel.opacities.last, 204);
    }, skip: !onWindows);

    test('does nothing while the overlay is not up', () {
      // No `arrange`, so nothing has been shown.
      controller.refreshOpacity();
      expect(channel.opacities, isEmpty);
    }, skip: !onWindows);
  });

  // The first call of a session, when no avatar is cached yet and every one of
  // them is a real request. The overlay used to be drawn only after all of
  // them came back — and a roster that changed while a fetch was out, which is
  // what a call does while it connects, abandoned the draw entirely. So the
  // overlay never appeared until the *next* call, by which point the avatars
  // were cached and it was instant.
  group('showing before the avatars arrive', () {
    /// A fetch that never completes, standing in for a media endpoint that has
    /// gone away. Without the timeout in `fetchAvatarBytes` this is also what
    /// a slow homeserver looks like.
    Future<Uint8List?> never(String mxc, int pixels) =>
        Completer<Uint8List?>().future;

    test('the overlay comes up even if no avatar ever does', () async {
      final slow = OverlayController(
        channel: channel,
        persistLayout: (_) {},
        fetchAvatar: never,
      );
      addTearDown(slow.dispose);

      await slow.setPrefs(const OverlayPrefsState(enabled: true));
      // Deliberately not awaited: the fetch never returns, so this future does
      // not either. The window still has to be up.
      unawaited(
        slow.setParticipants(
          inCall: true,
          participants: [_personWithAvatar('@a:example.org')],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(channel.shown, isTrue);
    }, skip: !onWindows);

    test('and a second time once they do', () async {
      var calls = 0;
      final quick = OverlayController(
        channel: channel,
        persistLayout: (_) {},
        fetchAvatar: (_, _) async {
          calls++;
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      addTearDown(quick.dispose);

      await quick.setPrefs(const OverlayPrefsState(enabled: true));
      await quick.setParticipants(
        inCall: true,
        participants: [_personWithAvatar('@a:example.org')],
      );

      expect(calls, 1);
      // Twice: the window came up carrying the initials-only snapshot inside
      // `show`, and the filled-in roster followed as a push.
      expect(channel.shown, isTrue, reason: 'first draw rides on show');
      expect(channel.pushes, greaterThanOrEqualTo(1), reason: 'then redrawn');
    }, skip: !onWindows);
  });
}

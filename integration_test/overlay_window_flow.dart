// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/overlay/overlay_app.dart';
import 'package:hardline/features/overlay/overlay_channel.dart';
import 'package:hardline/features/overlay/overlay_controller.dart';
import 'package:hardline/features/overlay/overlay_layout.dart';
import 'package:hardline/features/overlay/overlay_prefs_state.dart';
import 'package:hardline/features/overlay/overlay_wire.dart';
import 'package:hardline/features/voice/live_participant.dart';
import 'package:hardline/features/voice/speaking_participants.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';
import 'support/win32.dart';

// The real overlay: the runner's layered window, the second Flutter engine
// inside it, and the controller that drives both — with only the call faked.
//
// Everything here is asserted from a screen capture or from what Windows says
// about the window, never from what the controller believes it did. That is
// the point. The overlay has been wrong three times in ways the Dart side
// could not see: a monitor filled with white, a HUD drawn in purple, and a
// roster that was not there on the first call after launch.

/// Colours nothing else on a desktop is likely to be, so a count of exact
/// matches in a capture is a count of pixels the HUD painted.
///
/// The plate is deliberately not the shipped theme's. The overlay isolate
/// paints a compiled-in colour key until its first snapshot arrives, and that
/// key only matches the window's when the theme is the default one — so with
/// the default theme a HUD that has lost its snapshot is merely invisible,
/// and with this one it is an opaque sheet a capture cannot miss.
const _palette = OverlayPalette(
  speakingRing: 0xFF00E676,
  text: 0xFFFFFFFF,
  plate: 0xFF24507A,
);
const _plate = 0x24507A;

/// What the application window is filled with, so that seeing it *through*
/// the overlay is a colour that can be counted.
const _backdrop = 0xFF8800;

const _alice = '@alice:example.org';
const _bob = '@bob:example.org';
const _carol = '@carol:example.org';

/// So this suite can be driven on its own; see `all_test.dart`.
@pragma('vm:entry-point')
void overlayMain() => runOverlayApp();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  requireOwnDesktop();

  late OverlayChannel channel;
  late OverlayController controller;

  /// The part of the monitor the default layout puts the roster in.
  ScreenRect rosterArea() {
    final monitor = primaryMonitor;
    return ScreenRect(
      (monitor.width * 0.02).round(),
      (monitor.height * 0.08).round(),
      420,
      320,
    );
  }

  /// A patch of the application window well clear of the roster.
  ScreenRect backdropPatch() {
    final client = appWindow.clientArea;
    return ScreenRect(client.right - 300, client.bottom - 300, 200, 200);
  }

  int platePixels() => ScreenShot.of(rosterArea()).count(_plate);

  /// Whether the application window can be seen where the HUD is not.
  bool seeThrough() {
    final patch = backdropPatch();
    return ScreenShot.of(patch).count(_backdrop) == patch.width * patch.height;
  }

  Future<void> prepare(WidgetTester tester) async {
    await tester.pumpWidget(
      const ColoredBox(color: Color(0xFF000000 | _backdrop)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // The rest of the file reads the desktop. If the window these tests run
    // in is covered or off the primary monitor, every count below is of
    // somebody else's pixels.
    expect(
      seeThrough(),
      isTrue,
      reason:
          'The test window is not fully visible on the primary monitor. '
          'Leave it uncovered while the suite runs.',
    );
  }

  /// What `overlayDriverProvider` does at launch, in its order.
  Future<void> launch({
    double idleOpacity = 1,
    Duration linger = const Duration(seconds: 2),
  }) async {
    await controller.setPrefs(
      OverlayPrefsState(
        enabled: true,
        // Off, or the overlay is absent from every capture this file takes.
        excludeFromCapture: false,
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
    controller.setPalette(_palette);
    await controller.setParticipants(inCall: false, participants: const []);
    controller.setSpeaking(const SpeakingParticipants.silent());
  }

  Future<void> join(List<LiveParticipant> people) =>
      controller.setParticipants(inCall: true, participants: people);

  Future<void> hangUp(WidgetTester tester) async {
    controller.setSpeaking(const SpeakingParticipants.silent());
    await controller.setParticipants(inCall: false, participants: const []);
    await pumpUntil(
      tester,
      () => !(overlayWindow?.isVisible ?? false),
      reason: 'the overlay window to be hidden once the call has ended',
    );
  }

  setUp(() {
    channel = OverlayChannel();
    controller = OverlayController(
      channel: channel,
      persistLayout: (_) {},
      fetchAvatar: (_, _) async => null,
    );
  });

  tearDown(() async {
    await controller.dispose();
    await channel.dispose();
  });

  // TODOs.md 13, as it was reported: nothing on the first call after launch,
  // fine on every call after it, and back again after a restart.
  //
  // **This has to be the first test in the process to show the overlay**, and
  // it only means anything in an AOT build — `flutter drive --profile`. The
  // first `show` is what creates the second engine. In a debug build that
  // loads the kernel on the calling thread, which takes long enough that the
  // overlay's Dart is listening before the app sends anything else; in AOT it
  // returns in tens of milliseconds and the overlay used to miss the roster.
  testWidgets('the first call after launch draws the roster', (tester) async {
    await prepare(tester);
    expect(
      overlayWindow,
      isNull,
      reason:
          'Something showed the overlay before this test, so this is no '
          'longer the first call of the process. The overlay suite has to '
          'run first — see all_test.dart.',
    );

    await launch();
    await tester.pump(const Duration(milliseconds: 200));
    expect(overlayWindow, isNull, reason: 'nothing is shown outside a call');

    await join([person(_alice, name: 'Alice'), person(_bob, name: 'Bob')]);
    // What a live call does next: the speaking notifier fires as soon as
    // anybody makes a sound, and several times a second after that. These
    // are the messages that used to push the roster out.
    for (final ids in const [
      {_alice},
      <String>{},
      {_bob},
    ]) {
      controller.setSpeaking(
        SpeakingParticipants(roomId: '!r:example.org', userIds: ids),
      );
    }

    // From here until the roster is up, the screen must at no point be
    // covered. Before the overlay waited to be told its engine had drawn,
    // this stretch held a frame of the compiled-in colour key — which the
    // window is not keyed on in this palette, so it was an opaque sheet.
    final clock = Stopwatch()..start();
    var covered = 0;
    while (platePixels() < 1000) {
      if (!seeThrough()) covered++;
      if (clock.elapsed > const Duration(seconds: 8)) {
        fail(
          'The roster never appeared on the first call. If the log has '
          '"Could not resolve main entrypoint function", this was run with '
          '`flutter test`, under which the overlay engine cannot start — '
          'use `flutter drive`, see all_test.dart.',
        );
      }
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(covered, 0, reason: 'the desktop was covered while it came up');

    // And it is the roster, not a rectangle: the application shows through
    // around it, in the same capture.
    final roster = ScreenShot.of(rosterArea());
    await roster.save('first_call');
    expect(roster.count(_backdrop), greaterThan(50000));
    expect(seeThrough(), isTrue);

    final window = overlayWindow!;
    expect(window.layered.keyed, isTrue);
    expect(window.layered.colorKey, _palette.chromaKey & 0xFFFFFF);
    expect(window.layered.alpha, 255);

    await hangUp(tester);
  });

  // The other thing a window can hold that is not this call: the last frame
  // of the one before. The engine does not draw while its window is hidden,
  // so on the next `show` the old roster was on screen until the new snapshot
  // had been laid out — a frame or three of the wrong people.
  testWidgets('a later call never shows the roster of the one before', (
    tester,
  ) async {
    await prepare(tester);
    await launch();

    await join([
      person(_alice, name: 'Alice'),
      person(_bob, name: 'Bob'),
      person(_carol, name: 'Carol'),
    ]);
    await pumpUntil(
      tester,
      () => platePixels() > 1000,
      reason: 'the three-person roster to be drawn',
    );
    await tester.pump(const Duration(milliseconds: 200));
    final three = platePixels();
    await hangUp(tester);

    await join([person(_alice, name: 'Alice')]);
    final clock = Stopwatch()..start();
    var most = 0;
    while (clock.elapsed < const Duration(milliseconds: 1200)) {
      final now = platePixels();
      if (now > most) most = now;
      await tester.pump(const Duration(milliseconds: 5));
    }

    expect(most, greaterThan(500), reason: 'the one-person roster appeared');
    expect(
      most,
      lessThan(three * 0.6),
      reason:
          'At some point more of the plate was on screen than one person '
          'accounts for: the previous call was shown first.',
    );

    await hangUp(tester);
  });
}

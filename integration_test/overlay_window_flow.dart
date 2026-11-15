// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/hotkeys/hotkey.dart';
import 'package:hardline/features/hotkeys/hotkey_action.dart';
import 'package:hardline/features/hotkeys/hotkey_binder.dart';
import 'package:hardline/features/hotkeys/hotkeys_state.dart';
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

  /// Layouts the controller asked to have written back, newest last.
  late List<OverlayLayout> persisted;

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
    bool excludeFromCapture = false,
    String monitorId = '',
  }) async {
    await controller.setPrefs(
      OverlayPrefsState(
        enabled: true,
        // Off by default, or the overlay is absent from every capture this
        // file takes — which is the setting working, and one test's subject.
        excludeFromCapture: excludeFromCapture,
        monitorId: monitorId,
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
    persisted = [];
    controller = OverlayController(
      channel: channel,
      persistLayout: persisted.add,
      fetchAvatar: (_, _) async => null,
    );
  });

  tearDown(() async {
    await controller.dispose();
    await channel.dispose();
  });

  // The overlay bug as it was reported: nothing on the first call after launch,
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

  // ---------------------------------------------------------------------------
  // TODOs.md 4 — the parts of it one person and no game can check.
  // ---------------------------------------------------------------------------

  /// Joins a two-person call and waits until the roster is on screen.
  Future<void> showRoster(WidgetTester tester) async {
    await join([person(_alice, name: 'Alice'), person(_bob, name: 'Bob')]);
    await pumpUntil(
      tester,
      () => platePixels() > 1000,
      reason: 'the roster to be drawn',
    );
  }

  /// A point inside the first avatar, where the plate is solid.
  ({int x, int y}) insideRoster() {
    final area = rosterArea();
    return (x: area.left + 12, y: area.top + 26);
  }

  // 9.1. The gate the whole list hangs off: the HUD over the desktop with the
  // background fully transparent — not white, not black, not a rectangle.
  testWidgets('everything but the roster is the desktop', (tester) async {
    await prepare(tester);
    await launch();
    final before = ScreenShot.of(primaryMonitor);
    // A control, with no overlay yet: how much the desktop changes by itself
    // in about the time the roster takes to appear. A video or an animation
    // on this monitor fails the comparison below without anything being wrong
    // with the overlay, and this is what says so.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final drift = ScreenShot.of(primaryMonitor).differenceFrom(before);
    if (drift > 3000) {
      desktopIncidents.add(
        'the primary monitor changed by itself: $drift pixels in 500ms with '
        'no overlay on it, so the comparison of it below cannot be trusted',
      );
    }
    // The taskbar, if it is on this monitor. Windows 11 redraws it in another
    // shade when a window covers its monitor — measured: the whole 48-pixel
    // strip, every pixel of it, the moment the roster appeared — so it is
    // left out of the comparison below. What matters about it is checked
    // instead: it is still there, under the overlay, taking the clicks.
    final bar = taskbar?.bounds;
    final barOnThisMonitor =
        bar != null &&
        primaryMonitor.contains(bar.left + bar.width ~/ 2, bar.top);
    final barPoint = barOnThisMonitor
        ? (x: bar.left + bar.width ~/ 2, y: bar.top + bar.height ~/ 2)
        : null;
    await showRoster(tester);
    final after = ScreenShot.of(primaryMonitor);
    // Counted, never saved: this one is somebody's whole desktop.

    // The colour key itself must never reach the screen: keyed, it is a
    // hole; unkeyed, it is a sheet.
    expect(after.count(_palette.chromaKey), 0);

    if (barPoint != null) {
      expect(
        windowClassOf(windowUnder(barPoint.x, barPoint.y)),
        'Shell_TrayWnd',
        reason: 'the taskbar stays reachable under the overlay',
      );
    }

    // And the monitor is what it was, apart from a roster's worth of pixels.
    // Generous, because a desktop has a clock on it; a sheet over a
    // 3440x1440 monitor is five million pixels, not twenty thousand.
    final changed = after.differenceFrom(
      before,
      ignoring: barOnThisMonitor ? bar : null,
    );
    expect(changed, greaterThan(3000), reason: 'the roster is there');
    expect(
      changed,
      lessThan(60000),
      reason:
          'and little else moved. Roster at ${rosterArea()}; taskbar at '
          '$bar; changed pixels, taskbar included, '
          '${after.differenceMap(before)}',
    );
    await hangUp(tester);
  });

  // 9.2. The fade is the window's, and the linger is what stops it
  // flickering between two sentences.
  testWidgets('it holds while people talk, then fades to the idle opacity', (
    tester,
  ) async {
    await prepare(tester);
    await launch(idleOpacity: 0.4, linger: const Duration(milliseconds: 600));
    await showRoster(tester);
    final window = overlayWindow!;
    expect(window.layered.alpha, 255);

    // Talking, stopping, and talking again inside the linger: it never dips.
    controller.setSpeaking(
      const SpeakingParticipants(roomId: '!r:x', userIds: {_alice}),
    );
    var lowest = 255;
    final clock = Stopwatch()..start();
    while (clock.elapsed < const Duration(milliseconds: 1500)) {
      if (clock.elapsedMilliseconds % 500 > 250) {
        controller.setSpeaking(const SpeakingParticipants.silent());
      } else {
        controller.setSpeaking(
          const SpeakingParticipants(roomId: '!r:x', userIds: {_bob}),
        );
      }
      final alpha = window.layered.alpha;
      if (alpha < lowest) lowest = alpha;
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(lowest, 255, reason: 'a pause shorter than the linger is no pause');

    // Silence for longer than the linger: down to 40%, and that is what is
    // on the screen — the plate blended into the desktop behind it.
    controller.setSpeaking(const SpeakingParticipants.silent());
    await pumpUntil(
      tester,
      () => window.layered.alpha == 102,
      reason: 'the window to settle at 0.4 * 255 once the linger ran out',
    );
    await tester.pump(const Duration(milliseconds: 100));
    final point = insideRoster();
    final pixel = ScreenShot.of(rosterArea()).at(point.x, point.y);
    int blend(int shift) =>
        (((_plate >> shift) & 0xFF) * 102 +
            ((_backdrop >> shift) & 0xFF) * 153) ~/
        255;
    for (final shift in [16, 8, 0]) {
      expect(
        ((pixel >> shift) & 0xFF) - blend(shift),
        inInclusiveRange(-3, 3),
        reason: 'channel at bit $shift of ${pixel.toRadixString(16)}',
      );
    }

    // And one person talking brings the whole of it back.
    controller.setSpeaking(
      const SpeakingParticipants(roomId: '!r:x', userIds: {_alice}),
    );
    await pumpUntil(
      tester,
      () => window.layered.alpha == 255,
      reason: 'speech to bring the window back to full',
    );

    await hangUp(tester);
  });

  // 9.2, the other end: "nothing at all" means the window is still there and
  // nothing of it is.
  testWidgets('an idle opacity of zero leaves nothing on screen', (
    tester,
  ) async {
    await prepare(tester);
    await launch(idleOpacity: 0, linger: const Duration(milliseconds: 300));
    final before = ScreenShot.of(rosterArea());
    await showRoster(tester);

    await pumpUntil(
      tester,
      () => overlayWindow!.layered.alpha == 0,
      reason: 'the window to fade out entirely',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(overlayWindow!.isVisible, isTrue);
    expect(ScreenShot.of(rosterArea()).differenceFrom(before), 0);

    await hangUp(tester);
  });

  // 9.3 and 9.5. Clicks fall through, and the overlay stays above a window
  // that has just been given the foreground.
  testWidgets('clicks fall through it, and it stays on top', (tester) async {
    await prepare(tester);
    await launch();
    await showRoster(tester);
    final window = overlayWindow!;
    final point = insideRoster();

    expect(window.isClickThrough, isTrue);
    expect(window.isTopmost, isTrue);
    // Asked of Windows' own hit-testing, at a pixel the HUD has painted: a
    // click there goes to the application underneath.
    expect(windowUnder(point.x, point.y), appWindow.handle);
    expect(window.isForeground, isFalse, reason: 'showing must not take focus');

    appWindow.bringToFront();
    await tester.pump(const Duration(milliseconds: 300));
    expect(platePixels(), greaterThan(1000), reason: 'still drawn over it');

    await hangUp(tester);
  });

  // 9.6 and 9.7. The edit chord makes the HUD something that can be dragged,
  // and where it is dropped is what gets stored — as a fraction of the
  // monitor, not as pixels.
  testWidgets('edit mode takes the mouse, and a drag moves the layout', (
    tester,
  ) async {
    await prepare(tester);
    await launch();
    await showRoster(tester);
    final window = overlayWindow!;
    final monitor = primaryMonitor;
    final start = insideRoster();

    controller.setEditing(true);
    await pumpUntil(
      tester,
      () => !window.isClickThrough,
      reason: 'the overlay to stop being click-through in edit mode',
    );
    expect(windowUnder(start.x, start.y), window.handle);
    // Edit mode covers the monitor, deliberately: there is nothing else for
    // the pointer to land on while the button is down.
    await pumpUntil(
      tester,
      () => !seeThrough(),
      reason: 'the edit backdrop to cover the desktop',
    );

    await dragMouse(
      fromX: start.x,
      fromY: start.y,
      toX: start.x + 400,
      toY: start.y + 200,
      settle: () => tester.pump(const Duration(milliseconds: 40)),
    );
    await pumpUntil(
      tester,
      () => persisted.isNotEmpty,
      reason: 'the dragged position to come back from the overlay engine',
    );

    // The gesture recogniser spends the first few pixels deciding it is a
    // drag, so the distance is near 400 by 200 rather than exactly it.
    final moved = persisted.last;
    expect(
      (moved.x - 0.02) * monitor.width,
      inInclusiveRange(340, 400),
      reason: 'x moved by about the drag, as a fraction of the monitor',
    );
    expect((moved.y - 0.08) * monitor.height, inInclusiveRange(150, 200));

    controller.setEditing(false);
    await pumpUntil(
      tester,
      () => window.isClickThrough && seeThrough(),
      reason: 'the overlay to hand the desktop back after edit mode',
    );

    await hangUp(tester);
  });

  // 9.6. The chords, through the one registry, against the real window.
  testWidgets('the toggle chord hides it and brings it back', (tester) async {
    const toggle = Hotkey(
      modifiers: modControl | modAlt | modShift,
      key: 0x7A, // F11
    );
    expect(chordIsFree(toggle.modifiers, toggle.key), isTrue);

    await prepare(tester);
    await launch();
    final binder = HotkeyBinder(
      channel: channel,
      controller: FakeCallController(),
      overlay: controller,
    );
    addTearDown(binder.dispose);
    await binder.apply(
      const HotkeysState(bindings: {HotkeyAction.overlayToggle: toggle}),
      overlayEnabled: true,
    );
    await showRoster(tester);

    pressChord(toggle.modifiers, toggle.key);
    await pumpUntil(
      tester,
      () => !overlayWindow!.isVisible,
      reason: 'the toggle chord to hide the overlay',
    );
    expect(seeThrough(), isTrue);

    pressChord(toggle.modifiers, toggle.key);
    await pumpUntil(
      tester,
      () => platePixels() > 1000,
      reason: 'the same chord to bring it back',
    );

    await hangUp(tester);
    await binder.dispose();
    await pumpUntil(
      tester,
      () => chordIsFree(toggle.modifiers, toggle.key),
      reason: 'the chord to be released',
    );
  });

  // 9.10. A monitor named in a saved layout may have been unplugged since.
  testWidgets('a monitor that is not there falls back to the primary one', (
    tester,
  ) async {
    await prepare(tester);
    await launch(monitorId: r'\\.\DISPLAY_THAT_WAS_UNPLUGGED');
    await showRoster(tester);

    final bounds = overlayWindow!.bounds;
    final monitor = primaryMonitor;
    expect(bounds.left, monitor.left);
    expect(bounds.top, monitor.top);
    expect(bounds.width, monitor.width);
    expect(bounds.height, monitor.height);

    await hangUp(tester);
  });

  // 9.11. The capture these tests take is what a screen share takes, so a
  // window excluded from capture is absent from it exactly as it would be
  // from somebody's stream.
  testWidgets('hidden from capture, it is not in a capture', (tester) async {
    await prepare(tester);
    await launch(excludeFromCapture: true);
    await join([person(_alice, name: 'Alice'), person(_bob, name: 'Bob')]);

    // Up, opaque, and — to anything that captures the screen — not there.
    await pumpUntil(
      tester,
      () =>
          (overlayWindow?.isVisible ?? false) &&
          overlayWindow!.layered.alpha == 255,
      reason: 'the overlay window to be shown and revealed',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(platePixels(), 0);
    expect(seeThrough(), isTrue);

    // Switched off while it is up, and it is in the very next capture.
    await controller.setPrefs(
      const OverlayPrefsState(
        enabled: true,
        excludeFromCapture: false,
        layouts: [
          OverlayLayout(
            id: kDefaultOverlayLayoutId,
            name: 'Default',
            idleOpacity: 1,
          ),
        ],
      ),
    );
    await pumpUntil(
      tester,
      () => platePixels() > 1000,
      reason: 'the roster to appear in a capture once exclusion is off',
    );

    await hangUp(tester);
  });
}

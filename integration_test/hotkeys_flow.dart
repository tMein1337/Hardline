// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/hotkeys/hotkey.dart';
import 'package:hardline/features/hotkeys/hotkey_action.dart';
import 'package:hardline/features/hotkeys/hotkey_provider.dart';
import 'package:hardline/features/overlay/overlay_channel.dart';
import 'package:hardline/features/overlay/overlay_controller.dart';
import 'package:hardline/features/overlay/overlay_provider.dart';
import 'package:hardline/features/settings/panes/overlay_pane.dart';
import 'package:hardline/features/voice/call_controller_provider.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/win32.dart';

// Chords nothing else is likely to hold. The shipped Alt+Shift+O and
// Alt+Shift+P are deliberately not used: an installed copy of the app with its
// overlay switched on holds exactly those, and this must be runnable on the
// machine it was developed on.
const _all = modControl | modAlt | modShift;
const _f7 = Hotkey(modifiers: _all, key: 0x76);
const _f8 = Hotkey(modifiers: _all, key: 0x77);
const _f9 = Hotkey(modifiers: _all, key: 0x78);
const _f10 = Hotkey(modifiers: _all, key: 0x79);

bool _free(Hotkey chord) => chordIsFree(chord.modifiers, chord.key);

/// The overlay controller with the window taken away.
///
/// The chords under test end in two calls on this object. What those calls do
/// to a real overlay window is `overlay_window_flow.dart`'s subject; here it
/// would only put a HUD on the screen that this file has no reason to look at.
class _RecordingOverlay extends OverlayController {
  _RecordingOverlay(OverlayChannel channel)
    : super(
        channel: channel,
        persistLayout: (_) {},
        fetchAvatar: (_, _) async => null,
      );

  int toggles = 0;
  bool _editing = false;

  @override
  bool get editing => _editing;

  @override
  void toggleHidden() => toggles++;

  @override
  void setEditing(bool editing) => _editing = editing;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);

  late _RecordingOverlay overlay;

  /// Mounts the overlay pane over a store that binds the overlay pair to F7
  /// and F8, with the driver that keeps Windows in step running beside it —
  /// which in the app is `BackgroundWorkers`' job.
  Future<void> pumpPane(WidgetTester tester, {bool enabled = false}) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'call_hotkeys_v1': jsonEncode({
        'version': 2,
        HotkeyAction.overlayToggle.name: _f7.toJson(),
        HotkeyAction.overlayEdit.name: _f8.toJson(),
      }),
      'overlay_prefs_v1': jsonEncode({'enabled': enabled}),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          callControllerProvider.overrideWithValue(FakeCallController()),
          overlayControllerProvider.overrideWith((ref) {
            overlay = _RecordingOverlay(ref.watch(overlayChannelProvider));
            ref.onDispose(overlay.dispose);
            return overlay;
          }),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                ref.watch(hotkeyDriverProvider);
                return child!;
              },
              child: const OverlayPane(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Unmounts everything, and waits for Windows to have let go of the chords.
  ///
  /// Disposing the binder sends the releases; this is what makes sure a chord
  /// one test took is not still held when the next one asks whether it is free.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpUntil(
      tester,
      () => [_f7, _f8, _f9, _f10].every(_free),
      reason: 'every chord this file binds to be released on teardown',
    );
  }

  Finder chordButton(HotkeyAction action) => find.descendant(
    of: find.byKey(Key('hotkey_${action.name}')),
    matching: find.byType(OutlinedButton),
  );

  /// Binds [action] the way a person does: click the field, press the chord.
  Future<void> bind(
    WidgetTester tester,
    HotkeyAction action,
    LogicalKeyboardKey key,
  ) async {
    await tester.ensureVisible(chordButton(action));
    await tester.pumpAndSettle();
    await tester.tap(chordButton(action));
    await tester.pump();
    expect(find.text('Press a chord…'), findsOneWidget);

    const modifiers = [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.shiftLeft,
    ];
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pumpAndSettle();
  }

  setUp(() {
    // Anything already holding one of these makes every assertion below about
    // somebody else's program rather than this one.
    for (final chord in [_f7, _f8, _f9, _f10]) {
      expect(
        _free(chord),
        isTrue,
        reason:
            'Ctrl+Alt+Shift+F${chord.key - 0x6F} is held by another program, '
            'so this run cannot tell its own registrations from that one.',
      );
    }
  });

  // The behaviour the move to one registry had to preserve, asked of Windows
  // rather than of the binder: holding these while the overlay is off is what
  // once took Alt+Shift+O away from every other program on the machine.
  testWidgets('the overlay chords are held only while the overlay is on', (
    tester,
  ) async {
    await pumpPane(tester);
    expect(_free(_f7), isTrue);
    expect(_free(_f8), isTrue);

    await tester.tap(find.text('Show the overlay during calls'));
    await pumpUntil(
      tester,
      () => !_free(_f7) && !_free(_f8),
      reason: 'both overlay chords to be registered once the overlay is on',
    );

    await tester.tap(find.text('Show the overlay during calls'));
    await pumpUntil(
      tester,
      () => _free(_f7) && _free(_f8),
      reason: 'both overlay chords to be released once the overlay is off',
    );

    await unmount(tester);
  });

  testWidgets('a chord bound in settings is the one Windows delivers', (
    tester,
  ) async {
    await pumpPane(tester, enabled: true);
    await pumpUntil(
      tester,
      () => !_free(_f8),
      reason: 'the stored edit chord to be registered at launch',
    );

    await bind(tester, HotkeyAction.overlayEdit, LogicalKeyboardKey.f9);
    expect(find.text('Ctrl + Alt + Shift + F9'), findsOneWidget);
    await pumpUntil(
      tester,
      () => _free(_f8) && !_free(_f9),
      reason: 'the old chord to be released and the new one taken',
    );

    // From the keyboard, through the window manager and the runner's message
    // window, back into Dart. Nothing in the app is told this happened except
    // by `WM_HOTKEY`.
    pressChord(_f9.modifiers, _f9.key);
    await pumpUntil(
      tester,
      () => overlay.editing,
      reason: 'the edit chord to arrive as a hotkey and enter edit mode',
    );
    pressChord(_f9.modifiers, _f9.key);
    await pumpUntil(
      tester,
      () => !overlay.editing,
      reason: 'a second press to leave edit mode again',
    );

    pressChord(_f7.modifiers, _f7.key);
    await pumpUntil(
      tester,
      () => overlay.toggles == 1,
      reason: 'the toggle chord to arrive exactly once',
    );

    await unmount(tester);
  });

  testWidgets('unbinding a chord gives it back to the machine', (tester) async {
    await pumpPane(tester, enabled: true);
    await pumpUntil(tester, () => !_free(_f7), reason: 'the toggle chord');

    final unbind = find.descendant(
      of: find.byKey(Key('hotkey_${HotkeyAction.overlayToggle.name}')),
      matching: find.byTooltip('Unbind'),
    );
    await tester.ensureVisible(unbind);
    await tester.pumpAndSettle();
    await tester.tap(unbind);
    await tester.pumpAndSettle();

    await pumpUntil(tester, () => _free(_f7), reason: 'the chord to be freed');
    expect(
      find.descendant(
        of: chordButton(HotkeyAction.overlayToggle),
        matching: find.text('Not set'),
      ),
      findsOneWidget,
    );
    // The other one is somebody else's binding and must not have moved.
    expect(_free(_f8), isFalse);

    await unmount(tester);
  });

  // TODOs.md 9.6: "A chord another program already holds must be refused
  // visibly, not silently ignored."
  testWidgets('a chord another program holds is refused where it shows', (
    tester,
  ) async {
    final release = holdChord(_f10.modifiers, _f10.key);
    expect(release, isNotNull);
    addTearDown(release!);

    await pumpPane(tester, enabled: true);
    await bind(tester, HotkeyAction.overlayToggle, LogicalKeyboardKey.f10);

    // Windows answers after the rebuild the binding itself caused, so this
    // only ever appears if the pane is listening for the answer.
    await pumpUntil(
      tester,
      () =>
          find.textContaining('Windows refused this chord').evaluate().length ==
          1,
      reason: 'the refusal to appear under the row that asked for the chord',
    );

    // Rebinding to something that is free clears it again.
    await bind(tester, HotkeyAction.overlayToggle, LogicalKeyboardKey.f9);
    await pumpUntil(
      tester,
      () =>
          find.textContaining('Windows refused this chord').evaluate().isEmpty,
      reason: 'the refusal to go once the chord is one Windows will give us',
    );
    expect(_free(_f9), isFalse);

    release();
    await unmount(tester);
  });

  testWidgets('one chord on two actions names the other action', (
    tester,
  ) async {
    await pumpPane(tester, enabled: true);

    await bind(tester, HotkeyAction.overlayToggle, LogicalKeyboardKey.f8);

    // Both rows say so, each naming the other — and neither blames another
    // program, which is what a bare refusal from Windows would have said.
    expect(
      find.text(
        'Also bound to "${HotkeyAction.overlayEdit.label}". '
        'Only one of the two will fire.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Also bound to "${HotkeyAction.overlayToggle.label}". '
        'Only one of the two will fire.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Windows refused this chord'), findsNothing);

    await unmount(tester);
  });

  // With the overlay off its chords are not registered, and the pane says so
  // instead of leaving somebody to wonder why theirs does nothing.
  testWidgets('says the chords are not bound while the overlay is off', (
    tester,
  ) async {
    await pumpPane(tester);
    expect(
      find.textContaining('not bound while the overlay is switched off'),
      findsOneWidget,
    );

    await tester.tap(find.text('Show the overlay during calls'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('held system-wide while the overlay is switched on'),
      findsOneWidget,
    );

    await unmount(tester);
  });
}

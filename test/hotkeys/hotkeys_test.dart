// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/hotkeys/hotkey.dart';
import 'package:hardline/features/hotkeys/hotkey_action.dart';
import 'package:hardline/features/hotkeys/hotkey_binder.dart';
import 'package:hardline/features/hotkeys/hotkeys_controller.dart';
import 'package:hardline/features/hotkeys/hotkeys_state.dart';
import 'package:hardline/features/overlay/overlay_channel.dart';
import 'package:hardline/features/overlay/overlay_controller.dart';
import 'package:hardline/features/voice/livekit_call_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _altShiftM = Hotkey(
  modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
  key: 0x4D,
);
const _altShiftD = Hotkey(
  modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
  key: 0x44,
);
const _ctrlF9 = Hotkey(modifiers: HotkeyModifier.control, key: 0x78);

/// Nothing bound at all, which is no longer what the default constructor means.
const _empty = HotkeysState(bindings: {});

/// Stands in for the runner's hotkey table.
///
/// Subclasses the real channel, the idiom `overlay_linger_test.dart` uses. It
/// answers the way Windows does where that matters to the binder: a chord
/// already held under another id is refused, and so is anything in [refuse],
/// which plays the part of a chord some other program got to first.
class _FakeChannel extends OverlayChannel {
  final _fired = StreamController<int>.broadcast(sync: true);

  /// id to chord, as the window manager would have it.
  final held = <int, Hotkey>{};
  final refuse = <Hotkey>{};
  final log = <String>[];

  /// How long a call takes to come back, to open a window for interleaving.
  Duration latency = Duration.zero;

  void fire(int id) => _fired.add(id);

  @override
  Stream<int> get hotkeys => _fired.stream;

  @override
  Future<bool> registerHotkey(int id, Hotkey hotkey) async {
    // Applied on the way in, like a message the runner handles in the order
    // it was sent; only the reply is late.
    log.add('register $id');
    held.remove(id);
    final ok = !refuse.contains(hotkey) && !held.containsValue(hotkey);
    if (ok) held[id] = hotkey;
    await Future<void>.delayed(latency);
    return ok;
  }

  @override
  Future<void> unregisterHotkey(int id) async {
    log.add('unregister $id');
    held.remove(id);
    await Future<void>.delayed(latency);
  }
}

class _FakeCall extends Fake implements LiveKitCallController {
  @override
  bool isInCall = false;
  @override
  bool micMuted = false;
  @override
  bool deafened = false;
  int sharesStopped = 0;

  @override
  Future<void> setMicMuted(bool muted, {bool persist = true}) async =>
      micMuted = muted;

  @override
  Future<void> setDeafened(bool deafened) async => this.deafened = deafened;

  @override
  Future<void> stopAllScreenShares() async => sharesStopped++;
}

class _FakeOverlay extends Fake implements OverlayController {
  int toggles = 0;

  @override
  bool editing = false;

  @override
  void toggleHidden() => toggles++;

  @override
  void setEditing(bool editing) => this.editing = editing;
}

/// Builds the controller over [stored], and returns the state it settles on.
Future<HotkeysState> _load(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container.read(hotkeysProvider);
}

void main() {
  // `OverlayChannel`'s constructor installs a method-call handler, which needs
  // a binding. It is a real channel underneath the fake.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HotkeyAction ids', () {
    // These are persisted and handed straight to RegisterHotKey. Reusing one
    // for a different action would silently repoint somebody's saved binding.
    test('are unique', () {
      final ids = HotkeyAction.values.map((a) => a.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    // The two the overlay registered itself, before one registry owned them
    // all. A binding persisted by that build names the id, so changing either
    // would repoint somebody's saved chord at the wrong action.
    test('keep the numbers the overlay used', () {
      expect(HotkeyAction.overlayToggle.id, 1);
      expect(HotkeyAction.overlayEdit.id, 2);
    });

    test('resolve by id, and ignore a number nothing claims', () {
      for (final action in HotkeyAction.values) {
        expect(HotkeyAction.byId(action.id), action);
      }
      expect(HotkeyAction.byId(99), isNull);
    });
  });

  group('HotkeyGate', () {
    // The behaviour the move had to preserve: the overlay's chords are held
    // only while the overlay is on, and the call's are held from launch
    // because they have to exist before the call does.
    test('gates the overlay pair and nothing else', () {
      expect(HotkeyAction.overlayToggle.gate, HotkeyGate.overlayEnabled);
      expect(HotkeyAction.overlayEdit.gate, HotkeyGate.overlayEnabled);
      for (final action in HotkeyAction.alwaysOn) {
        expect(action.gate, HotkeyGate.always);
      }
    });

    // The voice pane renders a row per `alwaysOn` action. Were an overlay
    // action to leak into it, its chord would get two rows in two panes.
    test('splits the actions between the two panes exactly once', () {
      expect({
        ...HotkeyAction.alwaysOn,
        ...HotkeyAction.overlay,
      }, HotkeyAction.values.toSet());
      expect(
        HotkeyAction.alwaysOn.toSet().intersection(
          HotkeyAction.overlay.toSet(),
        ),
        isEmpty,
      );
    });
  });

  group('shipped defaults', () {
    // Bound out of the box, unlike the call actions, and only because the
    // gate means they are not actually held until the overlay is switched on.
    test('bind the overlay pair to the chords it always used', () {
      const state = HotkeysState();
      expect(
        state[HotkeyAction.overlayToggle],
        const Hotkey(modifiers: 5, key: 0x4F),
      );
      expect(
        state[HotkeyAction.overlayEdit],
        const Hotkey(modifiers: 5, key: 0x50),
      );
    });

    test('leave every call action unbound', () {
      const state = HotkeysState();
      for (final action in HotkeyAction.alwaysOn) {
        expect(state[action], isNull, reason: action.name);
      }
    });
  });

  group('HotkeysState', () {
    test('round-trips through JSON', () {
      const before = HotkeysState(
        bindings: {
          HotkeyAction.toggleMute: _altShiftM,
          HotkeyAction.overlayToggle: _ctrlF9,
        },
      );
      expect(HotkeysState.fromJson(before.toJson()), before);
    });

    test('binds and unbinds', () {
      final bound = _empty.withBinding(HotkeyAction.toggleDeafen, _altShiftD);
      expect(bound[HotkeyAction.toggleDeafen], _altShiftD);

      final cleared = bound.withBinding(HotkeyAction.toggleDeafen, null);
      expect(cleared[HotkeyAction.toggleDeafen], isNull);
      expect(cleared.hasAny, isFalse);
    });

    // An unbound chord and no entry are the same fact, and keeping both
    // representations would mean every reader had to check twice.
    test('treats an unbound chord as no binding at all', () {
      final state = _empty.withBinding(
        HotkeyAction.toggleMute,
        const Hotkey.none(),
      );
      expect(state.hasAny, isFalse);
    });

    test('leaves other bindings alone when one changes', () {
      final state = _empty
          .withBinding(HotkeyAction.toggleMute, _altShiftM)
          .withBinding(HotkeyAction.toggleDeafen, _altShiftD);

      final changed = state.withBinding(HotkeyAction.toggleMute, null);
      expect(changed[HotkeyAction.toggleDeafen], _altShiftD);
    });

    // Preferences, not protocol: one unreadable entry costs its own binding
    // and nothing else. A settings pane that will not open because of a bad
    // key is worse than a chord that needs rebinding.
    test('drops entries it cannot read and keeps the rest', () {
      final state = HotkeysState.fromJson({
        'toggleMute': _altShiftM.toJson(),
        'toggleDeafen': 'not a map',
        'stopScreenShares': <String, Object?>{'modifiers': 'nonsense'},
        'somethingRemoved': _altShiftD.toJson(),
      });

      expect(state[HotkeyAction.toggleMute], _altShiftM);
      expect(state[HotkeyAction.toggleDeafen], isNull);
      // modifiers unreadable -> 0, and key missing -> 0, which is unbound.
      expect(state[HotkeyAction.stopScreenShares], isNull);
    });
  });

  // The overlay's chords used to live in `overlay_prefs_v1` as two named
  // fields. Moving the store must not silently rebind them, in either
  // direction: a customised chord has to survive, and a deliberately cleared
  // one must not come back as the default.
  group('adopting the overlay chords', () {
    test('takes a customised chord out of the overlay blob', () async {
      final state = await _load({
        'overlay_prefs_v1': jsonEncode({
          'toggleHotkey': _ctrlF9.toJson(),
          'editHotkey': _altShiftD.toJson(),
        }),
      });

      expect(state[HotkeyAction.overlayToggle], _ctrlF9);
      expect(state[HotkeyAction.overlayEdit], _altShiftD);
    });

    test(
      'keeps a cleared chord cleared rather than restoring the default',
      () async {
        final state = await _load({
          'overlay_prefs_v1': jsonEncode({
            'toggleHotkey': const Hotkey.none().toJson(),
          }),
        });

        expect(state[HotkeyAction.overlayToggle], isNull);
        // Untouched in that blob, so the shipped default still stands.
        expect(state[HotkeyAction.overlayEdit], isNotNull);
      },
    );

    test('leaves the defaults alone when there is no overlay blob', () async {
      final state = await _load({});
      expect(state[HotkeyAction.overlayToggle], isNotNull);
      expect(state[HotkeyAction.overlayEdit], isNotNull);
    });

    test('keeps call bindings already stored here', () async {
      final state = await _load({
        'call_hotkeys_v1': jsonEncode({'toggleMute': _altShiftM.toJson()}),
        'overlay_prefs_v1': jsonEncode({'toggleHotkey': _ctrlF9.toJson()}),
      });

      expect(state[HotkeyAction.toggleMute], _altShiftM);
      expect(state[HotkeyAction.overlayToggle], _ctrlF9);
    });

    // The version stamp is the only thing standing between a user who
    // deliberately unbound an overlay chord and having it handed back on every
    // launch, because the old blob still holds the chord they removed.
    test('does not run again once the store is stamped', () async {
      final state = await _load({
        'call_hotkeys_v1': jsonEncode({'version': 2}),
        'overlay_prefs_v1': jsonEncode({'toggleHotkey': _ctrlF9.toJson()}),
      });

      expect(state[HotkeyAction.overlayToggle], isNull);
      expect(state[HotkeyAction.overlayEdit], isNull);
    });

    test('stamps the store so the next launch skips it', () async {
      SharedPreferences.setMockInitialValues({
        'overlay_prefs_v1': jsonEncode({'toggleHotkey': _ctrlF9.toJson()}),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      container.read(hotkeysProvider);
      await Future<void>.delayed(Duration.zero);

      final written = jsonDecode(prefs.getString('call_hotkeys_v1')!) as Map;
      expect(written['version'], 2);
      expect(written['overlayToggle'], _ctrlF9.toJson());
    });

    test('survives an unreadable overlay blob', () async {
      final state = await _load({'overlay_prefs_v1': 'not json at all'});
      // Falls back to the shipped defaults rather than throwing during build.
      expect(state[HotkeyAction.overlayToggle], isNotNull);
    });
  });

  group('HotkeyBinder', () {
    late _FakeChannel channel;
    late _FakeCall call;
    late _FakeOverlay overlay;
    late HotkeyBinder binder;

    setUp(() {
      channel = _FakeChannel();
      call = _FakeCall();
      overlay = _FakeOverlay();
      binder = HotkeyBinder(
        channel: channel,
        controller: call,
        overlay: overlay,
      );
    });

    tearDown(() => binder.dispose());

    /// The shipped overlay pair, plus a mute chord somebody bound.
    final bindings = const HotkeysState().withBinding(
      HotkeyAction.toggleMute,
      _altShiftM,
    );

    // The behaviour the move had to preserve. Holding the overlay's chords
    // while the overlay is off is what took Alt+Shift+O away from every other
    // program on the machine.
    test('holds the overlay pair only while the overlay is on', () async {
      await binder.apply(bindings, overlayEnabled: false);
      expect(channel.held.keys, {HotkeyAction.toggleMute.id});

      await binder.apply(bindings, overlayEnabled: true);
      expect(channel.held.keys, {
        HotkeyAction.overlayToggle.id,
        HotkeyAction.overlayEdit.id,
        HotkeyAction.toggleMute.id,
      });

      await binder.apply(bindings, overlayEnabled: false);
      expect(channel.held.keys, {HotkeyAction.toggleMute.id});
    });

    // This runs on every preference write, and each chord is an unregister
    // and a register against the window manager.
    test('touches nothing when nothing changed', () async {
      await binder.apply(bindings, overlayEnabled: true);
      channel.log.clear();

      await binder.apply(bindings, overlayEnabled: true);
      expect(channel.log, isEmpty);
    });

    test('re-registers only the chord that moved', () async {
      await binder.apply(bindings, overlayEnabled: true);
      channel.log.clear();

      await binder.apply(
        bindings.withBinding(HotkeyAction.toggleMute, _altShiftD),
        overlayEnabled: true,
      );
      expect(channel.log, ['register ${HotkeyAction.toggleMute.id}']);
      expect(channel.held[HotkeyAction.toggleMute.id], _altShiftD);
    });

    // Windows refuses a chord that is already registered, to us as much as to
    // anybody. Handing one from an action to another in a single write only
    // works if the old owner has let go before the new one asks.
    test('releases before it registers, so a chord can change hands', () async {
      await binder.apply(bindings, overlayEnabled: true);

      await binder.apply(
        bindings
            .withBinding(HotkeyAction.toggleMute, null)
            .withBinding(HotkeyAction.toggleDeafen, _altShiftM),
        overlayEnabled: true,
      );

      expect(channel.held[HotkeyAction.toggleDeafen.id], _altShiftM);
      expect(binder.rejected.value, isEmpty);
    });

    group('a chord Windows refuses', () {
      // The refusal arrives after the rebuild that binding the chord causes,
      // so a pane that only read the set at build time never showed it.
      test('is reported, to anything listening', () async {
        channel.refuse.add(_altShiftM);
        var notified = 0;
        binder.rejected.addListener(() => notified++);

        await binder.apply(bindings, overlayEnabled: false);

        expect(binder.rejected.value, {HotkeyAction.toggleMute});
        expect(notified, 1);
      });

      test('stops being reported once it is rebound', () async {
        channel.refuse.add(_altShiftM);
        await binder.apply(bindings, overlayEnabled: false);

        await binder.apply(
          bindings.withBinding(HotkeyAction.toggleMute, _altShiftD),
          overlayEnabled: false,
        );
        expect(binder.rejected.value, isEmpty);
      });

      test('stops being reported once it is unbound', () async {
        channel.refuse.add(_altShiftM);
        await binder.apply(bindings, overlayEnabled: false);

        await binder.apply(
          bindings.withBinding(HotkeyAction.toggleMute, null),
          overlayEnabled: false,
        );
        expect(binder.rejected.value, isEmpty);
      });

      // An overlay chord that was refused and is then gated off is no longer
      // being asked for, so there is nothing left to complain about.
      test('stops being reported once the gate closes', () async {
        channel.refuse.add(kDefaultHotkeys[HotkeyAction.overlayToggle]!);
        await binder.apply(bindings, overlayEnabled: true);
        expect(binder.rejected.value, {HotkeyAction.overlayToggle});

        await binder.apply(bindings, overlayEnabled: false);
        expect(binder.rejected.value, isEmpty);
      });
    });

    // The driver fires `apply` without awaiting it, once per preference write.
    // Each pass awaits the runner between chords, so two of them interleaved
    // used to diff against the same stale picture and the earlier one could
    // finish last.
    test('settles on the last of two overlapping passes', () async {
      channel.latency = const Duration(milliseconds: 5);

      final first = binder.apply(bindings, overlayEnabled: true);
      final second = binder.apply(bindings, overlayEnabled: false);
      await Future.wait([first, second]);

      expect(channel.held.keys, {HotkeyAction.toggleMute.id});
    });

    group('dispatch', () {
      test('runs the overlay chords whether or not a call is up', () {
        channel.fire(HotkeyAction.overlayToggle.id);
        expect(overlay.toggles, 1);

        channel.fire(HotkeyAction.overlayEdit.id);
        expect(overlay.editing, isTrue);
        channel.fire(HotkeyAction.overlayEdit.id);
        expect(overlay.editing, isFalse);
      });

      // Muting from inside a game while not in a call would be a silent no-op
      // at best, and at worst would flip a stored preference nobody saw move.
      test('ignores the call chords outside a call', () {
        channel.fire(HotkeyAction.toggleMute.id);
        channel.fire(HotkeyAction.toggleDeafen.id);
        channel.fire(HotkeyAction.stopScreenShares.id);

        expect(call.micMuted, isFalse);
        expect(call.deafened, isFalse);
        expect(call.sharesStopped, 0);
      });

      test('runs the call chords inside one', () {
        call.isInCall = true;

        channel.fire(HotkeyAction.toggleMute.id);
        expect(call.micMuted, isTrue);
        channel.fire(HotkeyAction.toggleMute.id);
        expect(call.micMuted, isFalse);

        channel.fire(HotkeyAction.toggleDeafen.id);
        expect(call.deafened, isTrue);

        channel.fire(HotkeyAction.stopScreenShares.id);
        expect(call.sharesStopped, 1);
      });

      test('ignores an id nothing claims', () {
        channel.fire(99);
        expect(overlay.toggles, 0);
      });
    });

    group('dispose', () {
      test('releases what it held and nothing else', () async {
        await binder.apply(bindings, overlayEnabled: false);
        channel.log.clear();

        await binder.dispose();
        expect(channel.log, ['unregister ${HotkeyAction.toggleMute.id}']);
        expect(channel.held, isEmpty);
      });

      // The provider rebuilds the binder when the account changes, and the
      // replacement registers straight away under the same ids. A dispose that
      // awaited between its own calls released the *new* binder's chords.
      test('does not release a chord its replacement just took', () async {
        channel.latency = const Duration(milliseconds: 5);
        await binder.apply(
          const HotkeysState(
            bindings: {
              HotkeyAction.toggleMute: _altShiftM,
              HotkeyAction.toggleDeafen: _altShiftD,
              HotkeyAction.stopScreenShares: _ctrlF9,
            },
          ),
          overlayEnabled: false,
        );

        final disposing = binder.dispose();
        final replacement = HotkeyBinder(
          channel: channel,
          controller: call,
          overlay: overlay,
        );
        addTearDown(replacement.dispose);
        // Only the last of the three, which is the one a sequential dispose
        // would reach after this registration had already landed.
        await replacement.apply(
          const HotkeysState(
            bindings: {HotkeyAction.stopScreenShares: _ctrlF9},
          ),
          overlayEnabled: false,
        );
        await disposing;

        expect(channel.held.keys, {HotkeyAction.stopScreenShares.id});
      });

      test('makes a later apply a no-op', () async {
        await binder.dispose();
        await binder.apply(bindings, overlayEnabled: true);
        expect(channel.held, isEmpty);
      });
    });
  });

  group('conflictingAction', () {
    test('finds a chord already bound to something else', () {
      final state = _empty
          .withBinding(HotkeyAction.toggleMute, _altShiftM)
          .withBinding(HotkeyAction.toggleDeafen, _altShiftD);

      expect(
        conflictingAction(state, HotkeyAction.stopScreenShares, _altShiftM),
        HotkeyAction.toggleMute,
      );
    });

    // The point of one store: a chord bound to a call action and an overlay
    // action is refused by Windows for whichever registers second, and only
    // one of them fires. Neither half could see the other before, so neither
    // could say that the program in the way was this one.
    test('sees across the call and overlay actions', () {
      final state = _empty.withBinding(HotkeyAction.overlayToggle, _altShiftM);
      expect(
        conflictingAction(state, HotkeyAction.toggleMute, _altShiftM),
        HotkeyAction.overlayToggle,
      );
    });

    test('does not report an action conflicting with itself', () {
      final state = _empty.withBinding(HotkeyAction.toggleMute, _altShiftM);
      expect(
        conflictingAction(state, HotkeyAction.toggleMute, _altShiftM),
        isNull,
      );
    });

    test('is null when the chord is free', () {
      final state = _empty.withBinding(HotkeyAction.toggleMute, _altShiftM);
      expect(
        conflictingAction(state, HotkeyAction.toggleDeafen, _altShiftD),
        isNull,
      );
    });
  });
}

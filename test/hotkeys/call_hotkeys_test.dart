// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/hotkeys/call_hotkey_binder.dart';
import 'package:hardline/features/hotkeys/call_hotkeys_state.dart';
import 'package:hardline/features/hotkeys/hotkey.dart';
import 'package:hardline/features/hotkeys/hotkey_action.dart';

const _altShiftM = Hotkey(
  modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
  key: 0x4D,
);
const _altShiftD = Hotkey(
  modifiers: HotkeyModifier.alt | HotkeyModifier.shift,
  key: 0x44,
);

void main() {
  group('HotkeyAction ids', () {
    // These are persisted and handed straight to RegisterHotKey. Reusing one
    // for a different action would silently repoint somebody's saved binding.
    test('are unique', () {
      final ids = HotkeyAction.values.map((a) => a.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('never collide with the overlay pair', () {
      for (final action in HotkeyAction.values) {
        expect(kOverlayHotkeyIds, isNot(contains(action.id)));
      }
    });
  });

  group('CallHotkeysState', () {
    test('starts with nothing bound', () {
      expect(const CallHotkeysState().hasAny, isFalse);
      expect(const CallHotkeysState()[HotkeyAction.toggleMute], isNull);
    });

    test('round-trips through JSON', () {
      const before = CallHotkeysState(
        bindings: {HotkeyAction.toggleMute: _altShiftM},
      );
      expect(CallHotkeysState.fromJson(before.toJson()), before);
    });

    test('binds and unbinds', () {
      final bound = const CallHotkeysState().withBinding(
        HotkeyAction.toggleDeafen,
        _altShiftD,
      );
      expect(bound[HotkeyAction.toggleDeafen], _altShiftD);

      final cleared = bound.withBinding(HotkeyAction.toggleDeafen, null);
      expect(cleared[HotkeyAction.toggleDeafen], isNull);
      expect(cleared.hasAny, isFalse);
    });

    // An unbound chord and no entry are the same fact, and keeping both
    // representations would mean every reader had to check twice.
    test('treats an unbound chord as no binding at all', () {
      final state = const CallHotkeysState().withBinding(
        HotkeyAction.toggleMute,
        const Hotkey.none(),
      );
      expect(state.hasAny, isFalse);
    });

    test('leaves other bindings alone when one changes', () {
      final state = const CallHotkeysState()
          .withBinding(HotkeyAction.toggleMute, _altShiftM)
          .withBinding(HotkeyAction.toggleDeafen, _altShiftD);

      final changed = state.withBinding(HotkeyAction.toggleMute, null);
      expect(changed[HotkeyAction.toggleDeafen], _altShiftD);
    });

    // Preferences, not protocol: one unreadable entry costs its own binding
    // and nothing else. A settings pane that will not open because of a bad
    // key is worse than a chord that needs rebinding.
    test('drops entries it cannot read and keeps the rest', () {
      final state = CallHotkeysState.fromJson({
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

  group('conflictingAction', () {
    test('finds a chord already bound to something else', () {
      final state = const CallHotkeysState()
          .withBinding(HotkeyAction.toggleMute, _altShiftM)
          .withBinding(HotkeyAction.toggleDeafen, _altShiftD);

      expect(
        conflictingAction(state, HotkeyAction.stopScreenShares, _altShiftM),
        HotkeyAction.toggleMute,
      );
    });

    test('does not report an action conflicting with itself', () {
      final state = const CallHotkeysState().withBinding(
        HotkeyAction.toggleMute,
        _altShiftM,
      );
      expect(
        conflictingAction(state, HotkeyAction.toggleMute, _altShiftM),
        isNull,
      );
    });

    test('is null when the chord is free', () {
      final state = const CallHotkeysState().withBinding(
        HotkeyAction.toggleMute,
        _altShiftM,
      );
      expect(
        conflictingAction(state, HotkeyAction.toggleDeafen, _altShiftD),
        isNull,
      );
    });
  });
}

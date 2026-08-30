// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import 'call_hotkeys_state.dart';
import 'hotkey.dart';
import 'hotkey_action.dart';

/// Not per account, for the same reason the overlay's chords are not: a global
/// chord belongs to the keyboard rather than to whoever happens to be signed
/// in, and rebinding it on every account switch would be a surprise.
const _prefsKey = 'call_hotkeys_v1';

/// Owns [CallHotkeysState] and persists it.
///
/// Structurally a copy of `OverlayPrefsController`, which is itself a copy of
/// `SecurityPrefsController`: read synchronously from the preferences injected
/// in `main()`, set state before the write so the change is on screen at once,
/// and treat a failed write as a lost preference rather than an error worth
/// interrupting anybody over.
class CallHotkeysController extends Notifier<CallHotkeysState> {
  @override
  CallHotkeysState build() {
    final raw = ref.read(prefsProvider).getString(_prefsKey);
    if (raw == null) return const CallHotkeysState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const CallHotkeysState();
      return CallHotkeysState.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      // Unreadable means nothing is bound, which is the safe direction: an
      // unbound action does nothing, where a wrongly bound one takes a chord
      // away from another program.
      return const CallHotkeysState();
    }
  }

  /// Binds [action], or clears it when [hotkey] is null or unbound.
  void setBinding(HotkeyAction action, Hotkey? hotkey) =>
      _write(state.withBinding(action, hotkey));

  void _write(CallHotkeysState next) {
    if (next == state) return;
    state = next;
    unawaited(
      ref.read(prefsProvider).setString(_prefsKey, jsonEncode(next.toJson())),
    );
  }
}

final callHotkeysProvider =
    NotifierProvider<CallHotkeysController, CallHotkeysState>(
      CallHotkeysController.new,
    );

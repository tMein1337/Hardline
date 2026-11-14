// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import 'hotkey.dart';
import 'hotkey_action.dart';
import 'hotkeys_state.dart';

/// Not per account, for the same reason the overlay's chords were not: a global
/// chord belongs to the keyboard rather than to whoever happens to be signed
/// in, and rebinding it on every account switch would be a surprise.
///
/// The name still says `call` because **the stored key cannot change without
/// losing what it holds**. It was written by a build where these were only the
/// call's chords; renaming it now would read as an empty store and silently
/// unbind whatever somebody had set.
const _prefsKey = 'call_hotkeys_v1';

/// The store's own version, distinct from the key's `_v1` suffix.
///
/// 1 held the three call actions and nothing else, because the overlay kept
/// its two in `overlay_prefs_v1`. 2 holds all five. The number is what stops
/// [_adoptOverlayChords] running twice — see there for why running it twice
/// would be worse than not running it at all.
const _schemaVersion = 2;

/// Where the overlay's chords used to live, read once to move them here.
const _overlayPrefsKey = 'overlay_prefs_v1';
const _legacyToggleKey = 'toggleHotkey';
const _legacyEditKey = 'editHotkey';

/// Owns [HotkeysState] and persists it.
///
/// Structurally a copy of `OverlayPrefsController`, which is itself a copy of
/// `SecurityPrefsController`: read synchronously from the preferences injected
/// in `main()`, set state before the write so the change is on screen at once,
/// and treat a failed write as a lost preference rather than an error worth
/// interrupting anybody over.
class HotkeysController extends Notifier<HotkeysState> {
  @override
  HotkeysState build() {
    final raw = ref.read(prefsProvider).getString(_prefsKey);

    Map<String, Object?>? decoded;
    if (raw != null) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map) decoded = parsed.cast<String, Object?>();
      } catch (_) {
        // Unreadable means nothing is bound, which is the safe direction: an
        // unbound action does nothing, where a wrongly bound one takes a chord
        // away from another program. Treated as absent rather than as empty, so
        // the migration below still gets its chance.
      }
    }

    final stored = decoded == null
        ? const HotkeysState()
        : HotkeysState.fromJson(decoded);

    final version = switch (decoded?['version']) {
      final int stamped => stamped,
      // Present but unstamped is the shape version 1 wrote.
      _ when decoded != null => 1,
      // Absent entirely. Still below the current version, because an install
      // that never opened the hotkey pane has no blob here and may still have
      // customised the overlay's chords in the overlay's own one.
      _ => 0,
    };

    if (version >= _schemaVersion) return stored;

    final migrated = _adoptOverlayChords(stored);
    // Persisted immediately rather than on the next edit, because the version
    // stamp is the only thing that stops this running again — and running it
    // again would resurrect a chord the user had since deliberately unbound.
    _persist(migrated);
    return migrated;
  }

  /// Moves the overlay's two chords out of `overlay_prefs_v1`.
  ///
  /// Reads that blob directly instead of going through `overlayPrefsProvider`.
  /// Watching it would make this controller depend on the overlay's, for one
  /// read, during a build — and the dependency would then survive forever to
  /// serve a migration that happens once.
  ///
  /// **A key that is present wins even when it is unbound.** Somebody who
  /// cleared the toggle chord in an earlier build meant to clear it, and
  /// falling back to the default there would hand them back the binding they
  /// had removed. Only a key that is *absent* leaves [kDefaultHotkeys] standing.
  HotkeysState _adoptOverlayChords(HotkeysState stored) {
    final raw = ref.read(prefsProvider).getString(_overlayPrefsKey);
    if (raw == null) return stored;

    Map<String, Object?> overlay;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return stored;
      overlay = parsed.cast<String, Object?>();
    } catch (_) {
      return stored;
    }

    var next = stored;
    for (final (action, key) in const [
      (HotkeyAction.overlayToggle, _legacyToggleKey),
      (HotkeyAction.overlayEdit, _legacyEditKey),
    ]) {
      final legacy = overlay[key];
      if (legacy is! Map) continue;
      final hotkey = Hotkey.fromJson(legacy.cast<String, Object?>());
      next = next.withBinding(action, hotkey.isBound ? hotkey : null);
    }
    return next;
  }

  /// Binds [action], or clears it when [hotkey] is null or unbound.
  void setBinding(HotkeyAction action, Hotkey? hotkey) =>
      _write(state.withBinding(action, hotkey));

  void _write(HotkeysState next) {
    if (next == state) return;
    state = next;
    _persist(next);
  }

  void _persist(HotkeysState next) => unawaited(
    ref
        .read(prefsProvider)
        .setString(
          _prefsKey,
          jsonEncode({'version': _schemaVersion, ...next.toJson()}),
        ),
  );
}

final hotkeysProvider = NotifierProvider<HotkeysController, HotkeysState>(
  HotkeysController.new,
);

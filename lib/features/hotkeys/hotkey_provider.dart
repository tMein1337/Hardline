// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../overlay/overlay_prefs_controller.dart';
import '../overlay/overlay_provider.dart';
import '../voice/call_controller_provider.dart';
import 'hotkey_binder.dart';
import 'hotkeys_controller.dart';

/// Owns the binder for the life of the app.
///
/// **Shares the overlay's channel**, and must. `OverlayChannel` wraps a static
/// `MethodChannel` whose handler is global per channel name, so a second
/// instance replaces the first one's handler and silently deafens it. This
/// used to build its own, which is exactly what stopped the overlay's toggle
/// and edit chords arriving.
///
/// It also holds the overlay *controller*, because the two chords that used to
/// be dispatched inside it are dispatched here now. The dependency runs one
/// way only — `overlayControllerProvider` knows nothing about the hotkeys —
/// so there is no cycle to break.
final hotkeyBinderProvider = Provider<HotkeyBinder>((ref) {
  final binder = HotkeyBinder(
    channel: ref.watch(overlayChannelProvider),
    controller: ref.watch(callControllerProvider),
    overlay: ref.watch(overlayControllerProvider),
  );
  ref.onDispose(() => unawaited(binder.dispose()));
  return binder;
});

/// Keeps Windows' idea of every global chord in step with the stored bindings.
///
/// A `Provider<void>` mounted for its side effects, the shape
/// `overlayDriverProvider` uses — and watched from `BackgroundWorkers` for the
/// same reason that one is: a chord has to be bound whether or not anybody has
/// opened the pane that describes it, or muting yourself from inside a game
/// would only work in sessions where you had visited settings first.
///
/// Two inputs, not one. The overlay's `enabled` switch gates its own two
/// chords, so flipping it has to re-apply — releasing them when the feature
/// goes off and taking them back when it returns. Watching the whole of
/// `overlayPrefsProvider` is deliberate over selecting `enabled`: it changes
/// only on a deliberate edit, and a re-apply with nothing changed returns
/// without touching the window manager.
final hotkeyDriverProvider = Provider<void>((ref) {
  final binder = ref.watch(hotkeyBinderProvider);
  unawaited(
    binder.apply(
      ref.watch(hotkeysProvider),
      overlayEnabled: ref.watch(overlayPrefsProvider).enabled,
    ),
  );
});

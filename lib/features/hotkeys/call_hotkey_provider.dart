// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../overlay/overlay_provider.dart';
import '../voice/call_controller_provider.dart';
import 'call_hotkey_binder.dart';
import 'call_hotkeys_controller.dart';

/// Owns the binder for the life of the app.
///
/// **Shares the overlay's channel**, and must. `OverlayChannel` wraps a static
/// `MethodChannel` whose handler is global per channel name, so a second
/// instance replaces the first one's handler and silently deafens it. This
/// used to build its own, which is exactly what stopped the overlay's toggle
/// and edit chords arriving.
final callHotkeyBinderProvider = Provider<CallHotkeyBinder>((ref) {
  final binder = CallHotkeyBinder(
    channel: ref.watch(overlayChannelProvider),
    controller: ref.watch(callControllerProvider),
  );
  ref.onDispose(() => unawaited(binder.dispose()));
  return binder;
});

/// Keeps Windows' idea of the call chords in step with the stored bindings.
///
/// A `Provider<void>` mounted for its side effects, the shape
/// `overlayDriverProvider` uses — and watched from `BackgroundWorkers` for the
/// same reason that one is: a chord has to be bound whether or not anybody has
/// opened the pane that describes it, or muting yourself from inside a game
/// would only work in sessions where you had visited settings first.
final callHotkeyDriverProvider = Provider<void>((ref) {
  final binder = ref.watch(callHotkeyBinderProvider);
  unawaited(binder.apply(ref.watch(callHotkeysProvider)));
});

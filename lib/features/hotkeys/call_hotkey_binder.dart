// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../overlay/overlay_channel.dart';
import '../voice/livekit_call_controller.dart';
import 'call_hotkeys_state.dart';
import 'hotkey.dart';
import 'hotkey_action.dart';

/// Keeps the operating system's idea of the call chords in step with the
/// user's, and runs them when they fire.
///
/// **Why this is not part of `OverlayController`**, which already owns two
/// chords and the channel they arrive on: that controller registers its pair
/// only while the overlay feature is switched on, and rightly so — holding a
/// global chord for a feature somebody has turned off takes it away from every
/// other program on the machine for nothing. But a mute chord has no such
/// relationship with the overlay, and binding it there would mean it stopped
/// working the moment the HUD was disabled, for no reason anybody could guess.
///
/// It also has no reference to the call controller: participants are pushed
/// *into* it from `overlayDriverProvider`, so there would have been nothing
/// there to mute.
///
/// The transport is shared, because there is only one — a single hidden
/// message window in the runner receives every `WM_HOTKEY` and forwards it by
/// id. Ids are allocated in [HotkeyAction]; [kOverlayHotkeyIds] records the
/// two this class must not touch.
class CallHotkeyBinder {
  CallHotkeyBinder({required this.channel, required this.controller}) {
    _subscription = channel.hotkeys.listen(_onHotkey);
  }

  final OverlayChannel channel;
  final LiveKitCallController controller;

  StreamSubscription<int>? _subscription;
  CallHotkeysState _bound = const CallHotkeysState();
  bool _disposed = false;

  /// Chords Windows refused, so the settings pane can say so.
  ///
  /// A refusal almost always means another program already holds the chord.
  /// That is a fact worth showing rather than an error worth retrying, and it
  /// cannot be known before asking.
  final Set<HotkeyAction> rejected = {};

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    for (final action in HotkeyAction.values) {
      await channel.unregisterHotkey(action.id);
    }
  }

  /// Registers what changed, and only what changed.
  ///
  /// Re-registering an unchanged chord would be harmless but is not free: each
  /// one is an unregister and a register against the window manager, and this
  /// runs on every preference write.
  Future<void> apply(CallHotkeysState next) async {
    if (_disposed || next == _bound) return;
    final previous = _bound;
    _bound = next;

    for (final action in HotkeyAction.values) {
      final before = previous[action];
      final after = next[action];
      if (before == after) continue;

      rejected.remove(action);
      if (after == null) {
        await channel.unregisterHotkey(action.id);
        continue;
      }

      final ok = await channel.registerHotkey(action.id, after);
      if (!ok) {
        rejected.add(action);
        debugPrint(
          '[hotkeys] Windows refused ${action.name}; another program is '
          'probably holding that chord',
        );
      }
    }
  }

  void _onHotkey(int id) {
    // The overlay's own ids arrive on this same stream. Ignoring them here
    // rather than assuming they cannot appear, because both halves listen.
    if (kOverlayHotkeyIds.contains(id)) return;

    final action = HotkeyAction.values.where((a) => a.id == id).firstOrNull;
    if (action == null) return;

    // Every one of these is meaningless outside a call, and firing them from
    // a game while not in one would be a silent no-op at best.
    if (!controller.isInCall) return;

    switch (action) {
      case HotkeyAction.toggleMute:
        unawaited(controller.setMicMuted(!controller.micMuted));
      case HotkeyAction.toggleDeafen:
        unawaited(controller.setDeafened(!controller.deafened));
      case HotkeyAction.stopScreenShares:
        unawaited(controller.stopAllScreenShares());
    }
  }
}

/// Whether [hotkey] is already bound to a different action.
///
/// Windows would accept the duplicate and then deliver only one of them, which
/// looks exactly like the second binding having silently failed.
HotkeyAction? conflictingAction(
  CallHotkeysState state,
  HotkeyAction action,
  Hotkey hotkey,
) {
  for (final entry in state.bindings.entries) {
    if (entry.key == action) continue;
    if (entry.value == hotkey) return entry.key;
  }
  return null;
}

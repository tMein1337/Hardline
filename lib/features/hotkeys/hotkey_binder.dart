// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../overlay/overlay_channel.dart';
import '../overlay/overlay_controller.dart';
import '../voice/livekit_call_controller.dart';
import 'hotkey.dart';
import 'hotkey_action.dart';
import 'hotkeys_state.dart';

/// Keeps the operating system's idea of the global chords in step with the
/// user's, and runs them when they fire.
///
/// **One registry for every chord**, which it was not: the overlay registered
/// and dispatched its own two from `OverlayController` while this handled the
/// call's three. Two claimants on one transport meant neither half could see
/// the other's bindings, so a chord given to both was refused by Windows for
/// whichever asked second — with nothing on either pane to say why.
///
/// What had to survive the move is the *gating*, not its location. The
/// overlay's chords are held only while the overlay is switched on, because
/// holding a global chord for a feature somebody turned off takes it away from
/// every other program for nothing. The call's chords cannot work that way:
/// they have to exist before the call does. So the gate is per action — see
/// [HotkeyGate] — rather than one switch over everything.
///
/// The transport is shared because there is only one: a single hidden message
/// window in the runner receives every `WM_HOTKEY` and forwards it by id.
class HotkeyBinder {
  HotkeyBinder({
    required this.channel,
    required this.controller,
    required this.overlay,
  }) {
    _subscription = channel.hotkeys.listen(_onHotkey);
  }

  final OverlayChannel channel;
  final LiveKitCallController controller;
  final OverlayController overlay;

  StreamSubscription<int>? _subscription;
  bool _disposed = false;

  /// What Windows currently holds on our behalf, after gating.
  ///
  /// Not the user's bindings: an overlay chord that is bound but gated off is
  /// absent here, which is what makes switching the overlay on register it and
  /// switching it off release it, with no separate bookkeeping.
  Map<HotkeyAction, Hotkey> _bound = const {};

  /// The tail of the queue [apply] runs on.
  Future<void> _applying = Future<void>.value();

  /// Chords Windows refused, so the settings pane can say so.
  ///
  /// A refusal almost always means another program already holds the chord.
  /// That is a fact worth showing rather than an error worth retrying, and it
  /// cannot be known before asking.
  ///
  /// A notifier rather than a plain set because the answer arrives *after* the
  /// rebuild that asked the question. Binding a chord writes the preference,
  /// the pane rebuilds at once, and only then does Windows get round to
  /// refusing it — so a pane that merely read the set drew the row as fine and
  /// kept it that way until something unrelated rebuilt it.
  ValueListenable<Set<HotkeyAction>> get rejected => _rejected;
  final _rejected = ValueNotifier<Set<HotkeyAction>>(const {});

  /// Releases every chord this binder holds.
  ///
  /// The unregisters are all *sent* before anything is awaited, and that is
  /// load-bearing. The provider that owns the binder rebuilds when the account
  /// changes, and the replacement registers its chords straight away under the
  /// same ids. Had this awaited between its own calls, the tail of them would
  /// have reached the runner after the replacement's registrations and quietly
  /// released chords that were no longer this object's to release.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final releases = [
      for (final action in _bound.keys) channel.unregisterHotkey(action.id),
    ];
    _bound = const {};

    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    await Future.wait(releases);
    _rejected.dispose();
  }

  /// Registers what changed, and only what changed.
  ///
  /// Re-registering an unchanged chord would be harmless but is not free: each
  /// one is an unregister and a register against the window manager, and this
  /// runs on every preference write.
  ///
  /// [overlayEnabled] is the overlay feature's own switch, which gates two of
  /// the five actions. It is passed in rather than read from a provider so the
  /// binder stays a plain object that a test can drive.
  ///
  /// Queued behind any pass already running. Each pass awaits the runner
  /// between chords and only records what it holds at the end, so two of them
  /// interleaved would each diff against the same stale picture — the overlay
  /// switched on and straight off again could leave its chords held, with this
  /// object convinced it had released them.
  Future<void> apply(HotkeysState next, {required bool overlayEnabled}) {
    final pass = _applying.then(
      (_) => _apply(next, overlayEnabled: overlayEnabled),
    );
    _applying = pass;
    return pass;
  }

  Future<void> _apply(HotkeysState next, {required bool overlayEnabled}) async {
    if (_disposed) return;

    final desired = <HotkeyAction, Hotkey>{};
    for (final action in HotkeyAction.values) {
      if (action.gate == HotkeyGate.overlayEnabled && !overlayEnabled) continue;
      final hotkey = next[action];
      if (hotkey == null || !hotkey.isBound) continue;
      desired[action] = hotkey;
    }

    if (mapEquals(desired, _bound)) return;

    final previous = _bound;
    // Recorded before the first await rather than after the last, so a
    // `dispose` arriving mid-pass releases what this pass is about to hold.
    _bound = desired;
    final rejected = {..._rejected.value};

    // Releases first, then registrations. Windows refuses a chord that is
    // already registered, including to another of our own ids — so moving a
    // chord from one action to another in a single pass only works if the old
    // owner has let go of it by the time the new one asks.
    for (final action in HotkeyAction.values) {
      if (!previous.containsKey(action) || desired.containsKey(action)) {
        continue;
      }
      rejected.remove(action);
      await channel.unregisterHotkey(action.id);
    }

    for (final action in HotkeyAction.values) {
      final after = desired[action];
      if (after == null || previous[action] == after) continue;
      if (_disposed) return;

      final ok = await channel.registerHotkey(action.id, after);
      if (ok) {
        rejected.remove(action);
      } else {
        rejected.add(action);
        debugPrint(
          '[hotkeys] Windows refused ${action.name}; another program is '
          'probably holding that chord',
        );
      }
    }

    if (_disposed) return;
    if (!setEquals(rejected, _rejected.value)) _rejected.value = rejected;
  }

  void _onHotkey(int id) {
    final action = HotkeyAction.byId(id);
    if (action == null) return;

    switch (action) {
      // The overlay's chords deliberately do not check for a call. Hiding the
      // HUD or dragging it into place are both things somebody may want to do
      // while setting the feature up, and `OverlayController` already decides
      // for itself whether there is anything to draw.
      case HotkeyAction.overlayToggle:
        overlay.toggleHidden();
      case HotkeyAction.overlayEdit:
        overlay.setEditing(!overlay.editing);

      // These three are meaningless outside a call, and firing them from a
      // game while not in one would be a silent no-op at best.
      case HotkeyAction.toggleMute:
        if (controller.isInCall) {
          unawaited(controller.setMicMuted(!controller.micMuted));
        }
      case HotkeyAction.toggleDeafen:
        if (controller.isInCall) {
          unawaited(controller.setDeafened(!controller.deafened));
        }
      case HotkeyAction.stopScreenShares:
        if (controller.isInCall) unawaited(controller.stopAllScreenShares());
    }
  }
}

/// Whether [hotkey] is already bound to a different action.
///
/// Windows refuses the second registration of a chord, so one of the two would
/// simply not fire. Now that one store holds every chord, this sees across the
/// call and overlay actions rather than only within one set — and names the
/// other action, which a bare refusal from Windows cannot.
HotkeyAction? conflictingAction(
  HotkeysState state,
  HotkeyAction action,
  Hotkey hotkey,
) {
  for (final entry in state.bindings.entries) {
    if (entry.key == action) continue;
    if (entry.value == hotkey) return entry.key;
  }
  return null;
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import 'call_controller_provider.dart';
import 'livekit_call_controller.dart';
import 'matrix_rtc_membership.dart';

/// Shortest gap between two sweeps.
///
/// The sweep is driven by the sync tick, which fires several times a second
/// during a busy sync. The scan itself is local and cheap, but a stale
/// membership is not urgent enough to look for that often.
const Duration _minInterval = Duration(seconds: 10);

/// Whether our own device still claims to be in the call in a room.
///
/// The invariant this expresses: *if we are not in a call here, our device must
/// not hold a live membership here.* Anything else is a lie to everyone else in
/// the room, and only we can withdraw it.
///
/// Two things it deliberately does not match:
///
///  * **Other devices of the same user.** The other laptop may genuinely be in
///    the call. MSC3757 per-device state keys exist precisely so those do not
///    collide, and clearing one from here would hang up a call happening
///    somewhere else.
///  * **A call we are actually in.** Obvious, but it is the whole reason this
///    takes [inCallHere] rather than deciding for itself.
///
/// A plain function over values rather than a method on the sweeper, so the
/// rule can be tested without a `Client` — the same reason
/// `staleRingReceiptTarget` is one.
bool ownMembershipIsStale({
  required List<MatrixRtcMembership> live,
  required String ownUserId,
  required String ownDeviceId,
  required bool inCallHere,
}) {
  if (inCallHere) return false;
  return live.any(
    (membership) =>
        membership.userId == ownUserId && membership.deviceId == ownDeviceId,
  );
}

/// Withdraws call memberships this device left behind.
///
/// Leaving a call means writing `{}` over our own membership state event, and
/// only the client can do it. Every exit that runs no code — a Task Manager
/// kill, a crash, a power cut — therefore leaves us advertised in a channel we
/// are not in until `expires`, which is hours.
///
/// `DelayedLeave` is the real fix for that, but it needs MSC4140, and Synapse
/// only offers that when `max_event_delay_duration` is configured. This is the
/// half that works everywhere: on the next launch, before anyone has noticed,
/// the membership is cleared from the client that left it.
///
/// It is written as a continuously-checked invariant rather than a one-shot at
/// startup, because the same repair is right whenever it becomes true — a
/// `leave()` whose state write failed on a flaky connection leaves exactly the
/// same wreckage, and there is no reason to wait for a restart to tidy it.
///
/// Deliberately narrow: it acts only on our own user *and* our own device id,
/// and only while the controller is completely idle.
class StaleMembershipSweeper {
  StaleMembershipSweeper(this._client, {required this.controller});

  final Client _client;

  /// Consulted for whether a call is in progress. Nothing may be swept while
  /// one is, since `join()` publishes the membership *before* the status
  /// reaches `connected` — a sweep in that gap would clear a call being joined.
  final LiveKitCallController controller;

  DateTime _lastSweep = DateTime.fromMillisecondsSinceEpoch(0);
  bool _running = false;

  /// Runs a sweep if one is due and there is anything it could act on.
  void maybeSweep() {
    if (_running) return;
    if (DateTime.now().difference(_lastSweep) < _minInterval) return;

    // Idle means idle. `roomId` outlives `status` on the failure path, so both
    // are checked — a half-torn-down join must not look like "no call".
    if (controller.status != CallStatus.idle || controller.roomId != null) {
      return;
    }

    final userId = _client.userID;
    final deviceId = _client.deviceID;
    if (userId == null || deviceId == null) return;

    // The cheap local pre-check that keeps this off the network almost always.
    // `liveMembershipsOf` reads room state the SDK already holds, so the
    // normal outcome — nothing stale anywhere — costs no requests at all.
    final stale = <Room>[
      for (final room in _client.rooms)
        if (!room.isSpace && room.membership == Membership.join)
          if (ownMembershipIsStale(
            live: liveMembershipsOf(room),
            ownUserId: userId,
            ownDeviceId: deviceId,
            inCallHere: false,
          ))
            room,
    ];
    if (stale.isEmpty) return;

    _lastSweep = DateTime.now();
    unawaited(_sweep(stale, userId: userId, deviceId: deviceId));
  }

  Future<void> _sweep(
    List<Room> rooms, {
    required String userId,
    required String deviceId,
  }) async {
    _running = true;
    try {
      for (final room in rooms) {
        // Re-checked per room: a sweep started while idle can still be running
        // when the user joins a call, and clearing the membership they just
        // published would drop them out of it.
        if (controller.status != CallStatus.idle) return;

        try {
          await _client.setRoomStateWithKey(
            room.id,
            kCallMemberEventType,
            MatrixRtcMembership.stateKeyFor(
              userId: userId,
              deviceId: deviceId,
            ),
            const {},
          );
          debugPrint('[voice] withdrew a stale membership in ${room.id}');
        } catch (error) {
          // Per room, so one forbidden or unreachable room does not stop the
          // rest. Failing leaves what we already had.
          debugPrint(
            '[voice] could not withdraw the membership in ${room.id}: $error',
          );
        }
      }
    } finally {
      _running = false;
    }
  }
}

final _staleMembershipSweeperProvider = Provider<StaleMembershipSweeper>(
  (ref) => StaleMembershipSweeper(
    ref.watch(clientProvider),
    // Safe to `watch` even though the controller is a `ChangeNotifier`: this
    // is a plain `Provider`, so it rebuilds when the *instance* is replaced —
    // on an account switch — and not when the controller notifies.
    controller: ref.watch(callControllerProvider),
  ),
);

/// Drives the sweep off the sync tick.
///
/// A side effect in a provider body, the same shape `staleRingSweepProvider`
/// uses: the sweeper throttles itself, so being called often is free, and the
/// tick is the only clock that matters here — a membership becomes visibly
/// stale exactly when a sync tells us what the room state is.
final staleMembershipSweepProvider = Provider<void>((ref) {
  ref.watch(matrixTickProvider);
  ref.read(_staleMembershipSweeperProvider).maybeSweep();
});

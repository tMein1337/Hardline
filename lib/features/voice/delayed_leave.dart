// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'matrix_rtc_membership.dart';

/// How many pages of scheduled events to walk before giving up.
///
/// The list is per user across every room, so it is normally one or two
/// entries. A bound rather than a `while (nextBatch != null)` because a server
/// that keeps handing back a cursor would otherwise spin the join forever —
/// the SDK's own implementation has exactly that bug
/// (`famedly_call_extension.dart`, which re-requests without passing `from`).
const int _maxScheduledPages = 10;

/// Has the homeserver withdraw our call membership if we stop saying we are
/// alive.
///
/// The problem this exists for: leaving a call means writing `{}` over our
/// `org.matrix.msc3401.call.member` state event, and **only the client can do
/// that**. A graceful quit is handled by the `AppLifecycleListener` in
/// `call_controller_provider.dart`, but a Task Manager kill, a crash or a power
/// cut runs no Dart code at all. The membership then stands until `expires`,
/// which is hours — everyone else keeps seeing us in a channel we are not in.
///
/// MSC4140 moves the withdrawal to the server. We schedule the `{}` write at
/// join time with a delay, then push its timer back every few seconds. While
/// we are alive it never fires; the moment we stop, it does. That inverts the
/// failure mode: the *absence* of a client is what removes us, so dying is now
/// the case that works rather than the case that leaks.
///
/// Two things are best-effort by design and neither is fatal:
///
///  * **The homeserver may not support it.** Synapse advertises
///    `org.matrix.msc4140` only when `max_event_delay_duration` is configured.
///    Unsupported means we fall back to what we had — the `expires` deadline
///    and `StaleMembershipSweeper` catching it on next launch.
///  * **Arming may fail.** A call you can hear is worth more than tidy state,
///    so a failure here logs and lets the join continue.
class DelayedLeave {
  DelayedLeave({
    required this.client,
    required this.roomId,
    required this.stateKey,
    required this.onServerWithdrewMembership,
  });

  final Client client;
  final String roomId;

  /// The MSC3757 per-device key our membership lives under. The scheduled
  /// event has to target exactly this, or it would clear somebody else's.
  final String stateKey;

  /// Called when the server withdrew us while we still believed we were in the
  /// call, so the caller can republish. See [_heartbeat].
  final Future<void> Function() onServerWithdrewMembership;

  String? _delayId;
  Timer? _timer;
  bool _disposed = false;

  /// Whether a withdrawal is currently scheduled on the server.
  bool get isArmed => _delayId != null;

  /// Schedules the withdrawal and starts the heartbeat.
  ///
  /// Returns normally whether or not it managed to arm anything; callers get
  /// the answer from [isArmed] if they care.
  Future<void> arm() async {
    if (_disposed || _delayId != null) return;

    try {
      if (!await _isSupported()) {
        debugPrint(
          '[voice] homeserver does not support MSC4140 delayed events; a hard '
          'kill will leave the membership up until it expires',
        );
        return;
      }

      // Before scheduling, not after. A previous run that was killed leaves its
      // withdrawal pending on the server; if we rejoin inside the delay window
      // it would fire a few seconds later and clear the membership we are about
      // to publish — we would vanish from the channel while sitting in the
      // call. Cancelling first is what makes rejoining after a crash safe.
      //
      // Its own try/catch: this is the narrower protection of the two, and
      // failing to list what is pending is no reason to give up on scheduling
      // the withdrawal that covers the next hard kill.
      try {
        await _cancelOrphans();
      } catch (error, stack) {
        debugPrint('[voice] listing scheduled leaves failed: $error\n$stack');
      }

      _delayId = await client.setRoomStateWithKeyWithDelay(
        roomId,
        kCallMemberEventType,
        stateKey,
        kDelayedLeaveAfter.inMilliseconds,
        // The MatrixRTC spelling of "left": empty content, not a redaction.
        const {},
      );
      if (_disposed) {
        await disarm();
        return;
      }

      _timer = Timer.periodic(kDelayedLeaveHeartbeat, (_) => _heartbeat());
      debugPrint('[voice] delayed leave armed for $roomId ($_delayId)');
    } catch (error, stack) {
      debugPrint('[voice] arming the delayed leave failed: $error\n$stack');
    }
  }

  /// Cancels the scheduled withdrawal, because we are leaving properly.
  ///
  /// Must run **before** the membership is cleared by hand: a withdrawal left
  /// pending would fire against whatever the state looks like later, which
  /// after an immediate rejoin is a membership we want to keep.
  ///
  /// Terminal — an instance belongs to one call and is never re-armed. Marking
  /// it disposed here is what closes the race where a `leave()` arrives while
  /// [arm] is still mid-flight: without it, `arm` would finish afterwards and
  /// leave a withdrawal scheduled for a call nobody is in, with a heartbeat
  /// running to keep it alive.
  Future<void> disarm() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;

    final delayId = _delayId;
    _delayId = null;
    if (delayId == null) return;

    try {
      await client.manageDelayedEvent(delayId, DelayedEventAction.cancel);
    } on MatrixException catch (error) {
      // Already fired or already cancelled — there is nothing left to cancel,
      // which is the outcome we wanted anyway.
      if (error.error != MatrixError.M_NOT_FOUND) {
        debugPrint('[voice] cancelling the delayed leave failed: $error');
      }
    } catch (error) {
      debugPrint('[voice] cancelling the delayed leave failed: $error');
    }
  }

  /// Stops the heartbeat without touching the server.
  ///
  /// For teardown paths that cannot await anything. The scheduled withdrawal
  /// is deliberately left standing: if we are being disposed without a clean
  /// leave, having it fire is exactly right.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _heartbeat() async {
    final delayId = _delayId;
    if (_disposed || delayId == null) return;

    try {
      await client.manageDelayedEvent(delayId, DelayedEventAction.restart);
    } on MatrixException catch (error) {
      if (error.error != MatrixError.M_NOT_FOUND) {
        // A transient failure. Three more heartbeats fit inside the delay
        // window, so one loss is not worth reacting to.
        debugPrint('[voice] delayed leave heartbeat failed: $error');
        return;
      }

      // The withdrawal already fired: enough heartbeats were missed that the
      // server believed us gone — a suspended laptop, a long network outage.
      // Our membership has been cleared underneath us, so republishing and
      // re-arming is what puts us back in the channel we never actually left.
      debugPrint('[voice] delayed leave fired early; republishing membership');
      _timer?.cancel();
      _timer = null;
      _delayId = null;
      if (_disposed) return;

      try {
        await onServerWithdrewMembership();
      } catch (error, stack) {
        debugPrint('[voice] republishing membership failed: $error\n$stack');
      }
      await arm();
    } catch (error) {
      debugPrint('[voice] delayed leave heartbeat failed: $error');
    }
  }

  /// Whether the homeserver implements MSC4140.
  ///
  /// `getVersions` is cached by the SDK for three days, so this is free after
  /// the first call and costs one request on a cold start.
  Future<bool> _isSupported() async {
    final versions = await client.getVersions();
    return versions.unstableFeatures?['org.matrix.msc4140'] ?? false;
  }

  /// Cancels withdrawals a previous run left pending for this exact membership.
  ///
  /// Matches on room, type *and* state key: the same account may legitimately
  /// have a pending withdrawal for another room or another device, and
  /// cancelling those would undo the protection they are providing.
  Future<void> _cancelOrphans() async {
    String? from;
    for (var page = 0; page < _maxScheduledPages; page++) {
      final response = await client.getScheduledDelayedEvents(from: from);

      for (final scheduled in response.scheduledEvents) {
        if (scheduled.roomId != roomId) continue;
        if (scheduled.type != kCallMemberEventType) continue;
        if (scheduled.stateKey != stateKey) continue;

        try {
          await client.manageDelayedEvent(
            scheduled.delayId,
            DelayedEventAction.cancel,
          );
          debugPrint(
            '[voice] cancelled a leftover delayed leave (${scheduled.delayId})',
          );
        } on MatrixException catch (error) {
          if (error.error != MatrixError.M_NOT_FOUND) rethrow;
        }
      }

      from = response.nextBatch;
      if (from == null || from.isEmpty) return;
    }
  }
}

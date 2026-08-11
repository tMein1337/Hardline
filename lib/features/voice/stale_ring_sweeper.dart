import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import 'matrix_rtc_membership.dart';
import 'voice_expiry_tick_provider.dart';

/// Shortest gap between two `/notifications` requests.
///
/// The sweep is driven by the sync tick, which fires several times a second
/// during a busy sync. This is what stops that becoming a request storm.
const Duration _minInterval = Duration(seconds: 20);

/// How many notifications to ask for.
///
/// Generous: the rule below refuses to act unless it can see *every* unread
/// notification in a room, so a truncated list simply means nothing is cleared.
const int _notificationLimit = 100;

/// The facts the staleness rule needs about one unread notification.
///
/// A record rather than a `MatrixEvent` so the rule can be tested with plain
/// values — the same reason `computeGroupingFlags` takes `GroupingEvent`.
typedef NotificationSummary = ({
  String eventId,
  String type,
  Map<String, Object?> content,
  DateTime originServerTs,
});

/// Which event to mark read to clear a room whose badge is only dead rings, or
/// null to leave the room alone.
///
/// Every condition here is a refusal, and deliberately so. Marking a room read
/// is destructive — a receipt cannot be taken back, and it clears everything
/// *before* the event it points at as well. So this acts only when it can prove
/// the badge is entirely rings for calls that are over:
///
///  * **Nothing unread** — nothing to do.
///  * **The call is still running** — the ring is answerable, and a badge for a
///    call you could still join is doing its job.
///  * **Anything unread that is not a ring** — a real message is in there.
///  * **Any ring still inside its lifetime** — it is ringing right now.
///  * **The server counts more than we can see** — [notificationCount] above
///    what the notification list showed means something unread did not come
///    back in the page, and clearing would silently swallow it.
///
/// Only when all of those pass is the newest unread ring returned.
String? staleRingReceiptTarget({
  required List<NotificationSummary> unread,
  required bool callIsLive,
  required int notificationCount,
  DateTime? now,
}) {
  if (unread.isEmpty || callIsLive) return null;
  if (notificationCount > unread.length) return null;

  final reference = now ?? DateTime.now();

  NotificationSummary? newest;
  for (final entry in unread) {
    if (!kRtcRingEventTypes.contains(entry.type)) return null;
    if (!isRingExpired(
      entry.content,
      originServerTs: entry.originServerTs,
      now: reference,
    )) {
      return null;
    }
    if (newest == null || entry.originServerTs.isAfter(newest.originServerTs)) {
      newest = entry;
    }
  }

  return newest?.eventId;
}

/// Clears unread badges left behind by calls that have ended.
///
/// A MatrixRTC ring is a doorbell: an ordinary timeline event carrying
/// `m.mentions: {room: true}`, so the homeserver's `@room` push rule gives it a
/// highlight and counts it against the room. Nothing withdraws it. Leaving a
/// call clears the *membership state event* — it does not touch the ring, which
/// stays in the timeline for good. And since this app renders no ring, the room
/// is left showing a red badge over an apparently empty conversation, for a
/// call that finished hours ago.
///
/// `/notifications` is what makes this safe rather than a guess: it returns the
/// actual events that produced each badge, so the rule above can insist that
/// *every* one of them is a dead ring before anything is marked read.
///
/// The receipt is **private** (`m.read.private`). It clears our own count
/// server-side, which is the entire point, while telling the room nothing —
/// announcing "read" for a doorbell nobody answered would be a claim about
/// having seen messages that were never sent. It also leaves `m.fully_read`
/// alone, so the unread line in any other client stays where the user put it.
class StaleRingSweeper {
  StaleRingSweeper(this._client);

  final Client _client;

  DateTime _lastSweep = DateTime.fromMillisecondsSinceEpoch(0);
  bool _running = false;

  /// Runs a sweep if one is due and there is anything it could act on.
  void maybeSweep() {
    if (_running) return;
    if (DateTime.now().difference(_lastSweep) < _minInterval) return;

    // The cheap pre-check that keeps this off the network almost always: no
    // highlighted room means no badge to clear, and that is the normal state.
    final highlighted = _client.rooms.where(
      (room) =>
          !room.isSpace &&
          room.membership == Membership.join &&
          room.highlightCount > 0,
    );
    if (highlighted.isEmpty) return;

    _lastSweep = DateTime.now();
    unawaited(_sweep());
  }

  Future<void> _sweep() async {
    _running = true;
    try {
      final response = await _client.getNotifications(
        limit: _notificationLimit,
        // Only highlighting events. A room whose badge is a ring has exactly
        // one kind of notification worth looking at, and asking for everything
        // would make the "did we see all of it" check fail on busy accounts.
        only: 'highlight',
      );

      final byRoom = <String, List<NotificationSummary>>{};
      for (final notification in response.notifications) {
        if (notification.read) continue;
        final event = notification.event;
        byRoom.putIfAbsent(notification.roomId, () => []).add((
          eventId: event.eventId,
          type: event.type,
          content: event.content,
          originServerTs: event.originServerTs,
        ));
      }

      for (final entry in byRoom.entries) {
        final room = _client.getRoomById(entry.key);
        if (room == null || room.membership != Membership.join) continue;

        final target = staleRingReceiptTarget(
          unread: [
            for (final summary in entry.value)
              if (summary.eventId.isNotEmpty) summary,
          ],
          callIsLive: liveMembershipsOf(room).isNotEmpty,
          // The highlight count, not the notification count: the request asked
          // for highlights only, so that is the number the list has to account
          // for.
          notificationCount: room.highlightCount,
        );
        if (target == null) continue;

        await _clear(room, target);
      }
    } catch (error) {
      // A sweep that did not run leaves a stale badge, which is what we had
      // before. Not worth a visible error.
      debugPrint('[voice] stale ring sweep failed: $error');
    } finally {
      _running = false;
    }
  }

  Future<void> _clear(Room room, String eventId) async {
    try {
      await _client.setReadMarker(room.id, mReadPrivate: eventId);
      debugPrint('[voice] cleared a dead call ring in ${room.id}');
    } catch (error) {
      debugPrint('[voice] could not clear the ring in ${room.id}: $error');
    }
  }
}

final _staleRingSweeperProvider = Provider<StaleRingSweeper>(
  (ref) => StaleRingSweeper(ref.watch(clientProvider)),
);

/// Drives the sweep off the two clocks that can make a ring go stale.
///
/// A side effect in a provider body, the same shape `roomListProvider` uses to
/// drive `HeroLoader`: the sweeper throttles itself, so being called often is
/// free, and the alternative — a timer of its own — would be a third clock for
/// something the existing two already answer.
///
///  * `matrixTickProvider` covers a call *ending*, which arrives as a sync.
///  * `voiceExpiryTickProvider` covers a ring simply *aging out*, which arrives
///    as nothing at all: the caller may never have hung up.
final staleRingSweepProvider = Provider<void>((ref) {
  ref.watch(matrixTickProvider);
  ref.watch(voiceExpiryTickProvider);
  ref.read(_staleRingSweeperProvider).maybeSweep();
});

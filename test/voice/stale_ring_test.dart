import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/features/voice/matrix_rtc_membership.dart';
import 'package:matrix_client/features/voice/stale_ring_sweeper.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 23, 40);

  /// A ring as Element actually sends one, sent [ago] before [now].
  NotificationSummary ring({
    required Duration ago,
    String eventId = r'$ring',
    int lifetime = 30000,
    bool withSenderTs = true,
    String type = 'org.matrix.msc4075.rtc.notification',
  }) {
    final sent = now.subtract(ago);
    return (
      eventId: eventId,
      type: type,
      content: {
        'lifetime': lifetime,
        'notification_type': 'notification',
        'm.mentions': {'room': true, 'user_ids': <String>[]},
        if (withSenderTs) 'sender_ts': sent.millisecondsSinceEpoch,
      },
      originServerTs: sent,
    );
  }

  NotificationSummary message({required Duration ago}) => (
    eventId: r'$msg',
    type: 'm.room.message',
    content: {'msgtype': 'm.text', 'body': 'are you there'},
    originServerTs: now.subtract(ago),
  );

  group('isRingExpired', () {
    test('a ring inside its lifetime is live', () {
      expect(
        isRingExpired(
          ring(ago: const Duration(seconds: 10)).content,
          originServerTs: now,
          now: now,
        ),
        isFalse,
      );
    });

    test('a ring past its lifetime is dead', () {
      expect(
        isRingExpired(
          ring(ago: const Duration(minutes: 5)).content,
          originServerTs: now,
          now: now,
        ),
        isTrue,
      );
    });

    // sender_ts is what MSC4075 defines the lifetime against, but it is
    // optional — a sender that omits it must not produce a ring that never
    // expires.
    test('falls back to origin_server_ts when sender_ts is missing', () {
      final entry = ring(
        ago: const Duration(minutes: 5),
        withSenderTs: false,
      );
      expect(
        isRingExpired(
          entry.content,
          originServerTs: entry.originServerTs,
          now: now,
        ),
        isTrue,
      );
    });

    test('a missing or nonsense lifetime falls back to the default', () {
      expect(
        isRingExpired(
          const {},
          originServerTs: now.subtract(const Duration(seconds: 45)),
          now: now,
        ),
        isTrue,
      );
      expect(
        isRingExpired(
          const {'lifetime': 0},
          originServerTs: now.subtract(const Duration(seconds: 10)),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('staleRingReceiptTarget', () {
    // The case from the screenshot: a friend started a call, it rang, they
    // left, and the badge stayed.
    test('clears a room whose only unread is a ring for an ended call', () {
      expect(
        staleRingReceiptTarget(
          unread: [ring(ago: const Duration(minutes: 4))],
          callIsLive: false,
          notificationCount: 1,
          now: now,
        ),
        r'$ring',
      );
    });

    test('leaves a call that is still running alone', () {
      expect(
        staleRingReceiptTarget(
          unread: [ring(ago: const Duration(minutes: 4))],
          callIsLive: true,
          notificationCount: 1,
          now: now,
        ),
        isNull,
      );
    });

    test('leaves a ring that is still ringing alone', () {
      expect(
        staleRingReceiptTarget(
          unread: [ring(ago: const Duration(seconds: 5))],
          callIsLive: false,
          notificationCount: 1,
          now: now,
        ),
        isNull,
      );
    });

    // The one that matters. A receipt clears everything before it too, so a
    // single real mention in the room has to veto the whole sweep.
    test('refuses when anything unread is not a ring', () {
      expect(
        staleRingReceiptTarget(
          unread: [
            ring(ago: const Duration(minutes: 4)),
            message(ago: const Duration(minutes: 2)),
          ],
          callIsLive: false,
          notificationCount: 2,
          now: now,
        ),
        isNull,
      );
    });

    // The server counting more than the notification page showed means
    // something unread did not come back, and clearing would swallow it.
    test('refuses when the server counts more than we can see', () {
      expect(
        staleRingReceiptTarget(
          unread: [ring(ago: const Duration(minutes: 4))],
          callIsLive: false,
          notificationCount: 7,
          now: now,
        ),
        isNull,
      );
    });

    test('nothing unread is nothing to do', () {
      expect(
        staleRingReceiptTarget(
          unread: const [],
          callIsLive: false,
          notificationCount: 0,
          now: now,
        ),
        isNull,
      );
    });

    test('points at the newest ring when a call rang more than once', () {
      expect(
        staleRingReceiptTarget(
          unread: [
            ring(ago: const Duration(minutes: 9), eventId: r'$old'),
            ring(ago: const Duration(minutes: 2), eventId: r'$new'),
            ring(ago: const Duration(minutes: 5), eventId: r'$mid'),
          ],
          callIsLive: false,
          notificationCount: 3,
          now: now,
        ),
        r'$new',
      );
    });

    // The MSC was renamed twice and clients in the wild still send the older
    // spellings; missing one would leave those badges stuck forever.
    test('recognises every spelling of the ring event', () {
      for (final type in kRtcRingEventTypes) {
        expect(
          staleRingReceiptTarget(
            unread: [ring(ago: const Duration(minutes: 4), type: type)],
            callIsLive: false,
            notificationCount: 1,
            now: now,
          ),
          r'$ring',
          reason: 'ring type $type should be recognised',
        );
      }
    });
  });
}

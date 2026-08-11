import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix_client/features/chat/message_grouping.dart';
import 'package:matrix_client/features/voice/matrix_rtc_membership.dart';

/// Base instant for readable relative timestamps.
final _t0 = DateTime(2026, 8, 4, 12, 0);

GroupingEvent _msg(String sender, Duration offset) => (
  senderId: sender,
  type: EventTypes.Message,
  timestamp: _t0.add(offset),
);

GroupingEvent _state(String sender, Duration offset) => (
  senderId: sender,
  type: EventTypes.RoomMember,
  timestamp: _t0.add(offset),
);

void main() {
  group('computeGroupingFlags', () {
    test('a single event starts a group and gets a date rule', () {
      final flags = computeGroupingFlags([_msg('@a:x', Duration.zero)]);

      expect(flags, hasLength(1));
      expect(flags.single.startsGroup, isTrue);
      expect(flags.single.crossesDay, isTrue);
    });

    test('empty input produces no flags', () {
      expect(computeGroupingFlags([]), isEmpty);
    });

    // This is the test that catches an inverted timeline. The input is
    // newest-first, so index 0 is the LATER message and index 1 the earlier
    // one. The later message must be the continuation.
    test('input is newest-first: index 0 is newer than index 1', () {
      final flags = computeGroupingFlags([
        _msg('@a:x', const Duration(minutes: 1)), // newer
        _msg('@a:x', Duration.zero), // older, and oldest overall
      ]);

      expect(
        flags[0].startsGroup,
        isFalse,
        reason: 'the newer message continues the older one',
      );
      expect(
        flags[1].startsGroup,
        isTrue,
        reason: 'the oldest loaded event always starts a block',
      );
    });

    test('same sender within the window collapses', () {
      final flags = computeGroupingFlags([
        _msg('@a:x', const Duration(minutes: 6)),
        _msg('@a:x', const Duration(minutes: 3)),
        _msg('@a:x', Duration.zero),
      ]);

      expect(flags[0].startsGroup, isFalse);
      expect(flags[1].startsGroup, isFalse);
      expect(flags[2].startsGroup, isTrue); // oldest
    });

    test('a gap longer than the window splits the block', () {
      final flags = computeGroupingFlags([
        _msg('@a:x', kGroupWindow + const Duration(minutes: 1)),
        _msg('@a:x', Duration.zero),
      ]);

      expect(flags[0].startsGroup, isTrue);
    });

    test('a gap exactly at the window still collapses', () {
      final flags = computeGroupingFlags([
        _msg('@a:x', kGroupWindow),
        _msg('@a:x', Duration.zero),
      ]);

      expect(flags[0].startsGroup, isFalse);
    });

    test('a different sender splits the block', () {
      final flags = computeGroupingFlags([
        _msg('@b:x', const Duration(minutes: 1)),
        _msg('@a:x', Duration.zero),
      ]);

      expect(flags[0].startsGroup, isTrue);
    });

    test('a state event breaks the block on both sides', () {
      final flags = computeGroupingFlags([
        _msg('@a:x', const Duration(minutes: 2)),
        _state('@a:x', const Duration(minutes: 1)),
        _msg('@a:x', Duration.zero),
      ]);

      // The message after a state event cannot continue the one before it.
      expect(flags[0].startsGroup, isTrue);
      // The state event itself is not a continuation either.
      expect(flags[1].startsGroup, isTrue);
    });

    test('crossing midnight splits the block and marks the day', () {
      final justAfterMidnight = DateTime(2026, 8, 5, 0, 1);
      final justBefore = DateTime(2026, 8, 4, 23, 59);

      final flags = computeGroupingFlags([
        (
          senderId: '@a:x',
          type: EventTypes.Message,
          timestamp: justAfterMidnight,
        ),
        (senderId: '@a:x', type: EventTypes.Message, timestamp: justBefore),
      ]);

      // Two minutes apart, same sender — only the date boundary splits them.
      expect(flags[0].crossesDay, isTrue);
      expect(flags[0].startsGroup, isTrue);
    });

    test('flags are index-aligned with the input', () {
      final events = [
        _msg('@a:x', const Duration(minutes: 2)),
        _msg('@b:x', const Duration(minutes: 1)),
        _msg('@c:x', Duration.zero),
      ];

      expect(computeGroupingFlags(events), hasLength(events.length));
    });
  });

  group('isRenderableType', () {
    test('messages and the state events worth showing', () {
      expect(isRenderableType(EventTypes.Message), isTrue);
      expect(isRenderableType(EventTypes.RoomMember), isTrue);
      expect(isRenderableType(EventTypes.RoomTopic), isTrue);
      expect(isRenderableType(EventTypes.Encryption), isTrue);
    });

    // A ring badges the room via `m.mentions: {room: true}`. Drawing nothing
    // for it is what produced a red 1 over an apparently empty conversation,
    // with nothing on screen to explain it. All three spellings, because the
    // MSC was renamed twice and clients in the wild still send the old ones.
    test('every spelling of the call ring renders', () {
      for (final type in kRtcRingEventTypes) {
        expect(isRenderableType(type), isTrue, reason: type);
      }
    });

    // The one that must stay excluded. Memberships change on every join, leave
    // and two-minute heartbeat; rendering them would bury the conversation
    // under call bookkeeping the room list already shows.
    test('the call membership stays out of the timeline', () {
      expect(isRenderableType(kCallMemberEventType), isFalse);
    });

    test('ordinary room noise stays out', () {
      expect(isRenderableType(EventTypes.RoomPowerLevels), isFalse);
      expect(isRenderableType('m.reaction'), isFalse);
      expect(isRenderableType('m.receipt'), isFalse);
    });
  });
}

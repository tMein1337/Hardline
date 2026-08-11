import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/features/activity/activity_reducers.dart';

void main() {
  final now = DateTime.utc(2026, 8, 11, 12);

  MessageRecord record(
    String eventId, {
    required String userId,
    required Duration ago,
    String roomId = '!room:example.org',
    String preview = 'hello',
  }) => MessageRecord(
    eventId: eventId,
    roomId: roomId,
    userId: userId,
    preview: preview,
    timestamp: now.subtract(ago),
  );

  group('previewOf', () {
    test('collapses whitespace to one line', () {
      expect(previewOf('one\n\ntwo   three\t'), 'one two three');
    });

    // A pasted essay would otherwise make one row as tall as the section.
    test('truncates long bodies with an ellipsis', () {
      final result = previewOf('a' * 500);
      expect(result.length, kPreviewLength + 1);
      expect(result.endsWith('…'), isTrue);
    });

    test('leaves a short body alone', () {
      expect(previewOf('  ship it  '), 'ship it');
    });
  });

  group('pruneActivities', () {
    test('orders newest first', () {
      final result = pruneActivities(
        [
          record('old', userId: '@a:x.org', ago: const Duration(hours: 2)),
          record('new', userId: '@a:x.org', ago: const Duration(minutes: 1)),
          record('mid', userId: '@a:x.org', ago: const Duration(minutes: 30)),
        ],
        now: now,
        horizon: const Duration(hours: 24),
        cap: 100,
      );

      expect(result.map((r) => r.eventId), ['new', 'mid', 'old']);
    });

    test('drops anything past the horizon', () {
      final result = pruneActivities(
        [
          record('kept', userId: '@a:x.org', ago: const Duration(hours: 23)),
          record('gone', userId: '@a:x.org', ago: const Duration(hours: 25)),
        ],
        now: now,
        horizon: const Duration(hours: 24),
        cap: 100,
      );

      expect(result.map((r) => r.eventId), ['kept']);
    });

    test('caps the length, keeping the newest', () {
      final result = pruneActivities(
        [
          for (var i = 0; i < 10; i++)
            record('e$i', userId: '@a:x.org', ago: Duration(minutes: i)),
        ],
        now: now,
        horizon: const Duration(hours: 24),
        cap: 3,
      );

      expect(result.map((r) => r.eventId), ['e0', 'e1', 'e2']);
    });

    // This is what stops the backfill from listing the seeded `lastEvent`
    // twice: both feed the same list, and both carry the same event id.
    test('collapses duplicate event ids, keeping the later copy', () {
      final result = pruneActivities(
        [
          record(
            'dup',
            userId: '@a:x.org',
            ago: const Duration(minutes: 5),
            preview: 'from the seed',
          ),
          record(
            'dup',
            userId: '@a:x.org',
            ago: const Duration(minutes: 5),
            preview: 'from the backfill',
          ),
        ],
        now: now,
        horizon: const Duration(hours: 24),
        cap: 100,
      );

      expect(result, hasLength(1));
      expect(result.single.preview, 'from the backfill');
    });
  });

  group('newestPerUser', () {
    final entries = pruneActivities(
      [
        record('a-old', userId: '@a:x.org', ago: const Duration(minutes: 20)),
        record('a-new', userId: '@a:x.org', ago: const Duration(minutes: 2)),
        record('b-new', userId: '@b:x.org', ago: const Duration(minutes: 5)),
        record('c-new', userId: '@c:x.org', ago: const Duration(minutes: 1)),
      ],
      now: now,
      horizon: const Duration(hours: 24),
      cap: 100,
    );

    test('keeps one entry per person, the latest', () {
      final result = newestPerUser(
        entries,
        {'@a:x.org', '@b:x.org'},
        now: now,
        window: const Duration(minutes: 30),
      );

      expect(result.keys.toSet(), {'@a:x.org', '@b:x.org'});
      expect(result['@a:x.org']!.eventId, 'a-new');
    });

    test('ignores people who are not followed', () {
      final result = newestPerUser(
        entries,
        {'@a:x.org'},
        now: now,
        window: const Duration(minutes: 30),
      );

      expect(result.keys, ['@a:x.org']);
    });

    test('honours the window', () {
      final result = newestPerUser(
        entries,
        {'@a:x.org', '@b:x.org'},
        now: now,
        window: const Duration(minutes: 3),
      );

      expect(result.keys, ['@a:x.org']);
    });

    test('following nobody is not a query', () {
      expect(
        newestPerUser(
          entries,
          const {},
          now: now,
          window: const Duration(hours: 1),
        ),
        isEmpty,
      );
    });
  });

  group('messagesOf', () {
    final entries = pruneActivities(
      [
        record('a1', userId: '@a:x.org', ago: const Duration(minutes: 1)),
        record('a2', userId: '@a:x.org', ago: const Duration(minutes: 2)),
        record('b1', userId: '@b:x.org', ago: const Duration(minutes: 3)),
        record('old', userId: '@a:x.org', ago: const Duration(hours: 5)),
      ],
      now: now,
      horizon: const Duration(hours: 24),
      cap: 100,
    );

    test('keeps every message from a followed person, newest first', () {
      final result = messagesOf(
        entries,
        {'@a:x.org'},
        now: now,
        window: const Duration(hours: 1),
        cap: 100,
      );

      expect(result.map((r) => r.eventId), ['a1', 'a2']);
    });

    test('caps the rows', () {
      final result = messagesOf(
        entries,
        {'@a:x.org', '@b:x.org'},
        now: now,
        window: const Duration(hours: 1),
        cap: 2,
      );

      expect(result.map((r) => r.eventId), ['a1', 'a2']);
    });
  });
}

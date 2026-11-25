// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/chat/chat_prefs.dart';
import 'package:hardline/features/notifications/desktop_notifications.dart';
import 'package:hardline/features/notifications/message_notifications.dart';
import 'package:hardline/features/notifications/notification_content.dart';
import 'package:hardline/features/shell/selection_providers.dart';
import 'package:hardline/features/spaces/space_summary.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_matrix.dart';

const _room = '!general:example.org';

class _RecordingSink implements NotificationSink {
  final shown = <NotificationContent>[];
  final cancelled = <String>[];

  @override
  Future<void> show(NotificationContent content) async => shown.add(content);

  @override
  Future<void> cancelRoom(String roomId) async => cancelled.add(roomId);
}

Event _message(
  Room room,
  String body, {
  String sender = '@alice:example.org',
  String id = r'$1',
  Map<String, Object?> extra = const {},
}) => Event(
  content: {'msgtype': MessageTypes.Text, 'body': body, ...extra},
  type: EventTypes.Message,
  eventId: id,
  senderId: sender,
  originServerTs: DateTime(2026),
  room: room,
);

void main() {
  late FakeMatrixClient client;
  late Room room;

  setUp(() {
    client = FakeMatrixClient();
    room = client.addRoom(
      _room,
      name: 'General',
      members: ['@alice:example.org'],
    );
    client.member(_room, '@alice:example.org', displayName: 'Alice');
  });

  group('describeNotification', () {
    test('names the room, the sender and what they said', () {
      final content = describeNotification(
        _message(room, 'hello there'),
        preview: true,
      )!;

      expect(content.title, 'General');
      expect(content.body, 'Alice: hello there');
      expect(parseNotificationPayload(content.payload), (
        roomId: _room,
        eventId: r'$1',
      ));
    });

    test('without a preview the text is never shown', () {
      final content = describeNotification(
        _message(room, 'the secret plan'),
        preview: false,
      )!;

      expect(content.body, isNot(contains('secret')));
      expect(content.body, 'Alice: New message');
    });

    test('a reply is shown without the quoted fallback', () {
      final content = describeNotification(
        _message(
          room,
          '> <@me:example.org> earlier\n\nanswer',
          extra: {
            'm.relates_to': {
              'm.in_reply_to': {'event_id': r'$0'},
            },
          },
        ),
        preview: true,
      )!;

      expect(content.body, 'Alice: answer');
    });

    test('an edit notifies nothing', () {
      final edit = _message(
        room,
        '* fixed',
        extra: {
          'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$0'},
        },
      );

      expect(describeNotification(edit, preview: true), isNull);
    });

    test('a very long message is cut short', () {
      final content = describeNotification(
        _message(room, 'x' * 2000),
        preview: true,
      )!;

      expect(content.body.length, lessThan(400));
    });
  });

  group('notificationIdForRoom', () {
    test('is stable, positive and differs between rooms', () {
      final a = notificationIdForRoom('!a:example.org');
      expect(a, notificationIdForRoom('!a:example.org'));
      expect(a, isNonNegative);
      expect(a, lessThan(1 << 31));
      expect(a, isNot(notificationIdForRoom('!b:example.org')));
    });
  });

  group('shouldNotify', () {
    const on = ChatPrefsState();

    test('not for the room being read while the app is in front', () {
      expect(
        shouldNotify(
          roomId: _room,
          prefs: on,
          appFocused: true,
          openRoomId: _room,
        ),
        isFalse,
      );
    });

    test('for that same room once the app is behind something else', () {
      expect(
        shouldNotify(
          roomId: _room,
          prefs: on,
          appFocused: false,
          openRoomId: _room,
        ),
        isTrue,
      );
    });

    test('for another room even while the app is in front', () {
      expect(
        shouldNotify(
          roomId: _room,
          prefs: on,
          appFocused: true,
          openRoomId: '!other:example.org',
        ),
        isTrue,
      );
    });

    test('never when switched off', () {
      expect(
        shouldNotify(
          roomId: _room,
          prefs: const ChatPrefsState(notify: false),
          appFocused: false,
          openRoomId: null,
        ),
        isFalse,
      );
    });
  });

  group('messageNotificationsProvider', () {
    late _RecordingSink sink;
    late ProviderContainer container;
    var focused = false;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      sink = _RecordingSink();
      focused = false;
      container = ProviderContainer(
        overrides: [
          clientProvider.overrideWithValue(client),
          prefsProvider.overrideWithValue(prefs),
          notificationSinkProvider.overrideWithValue(sink),
          appFocusedProvider.overrideWithValue(() => focused),
        ],
      );
      container.listen(messageNotificationsProvider, (_, _) {});
    });

    tearDown(() => container.dispose());

    Future<void> deliver(Event event) async {
      client.onNotification.add(event);
      await Future<void>.delayed(Duration.zero);
    }

    test('shows what the push rules hand over', () async {
      await deliver(_message(room, 'hi'));

      expect(sink.shown.single.body, 'Alice: hi');
    });

    test('ignores our own messages', () async {
      await deliver(_message(room, 'hi', sender: client.me));

      expect(sink.shown, isEmpty);
    });

    test('opening the room withdraws its notification', () async {
      await deliver(_message(room, 'hi'));

      container
          .read(selectedRoomIdsProvider.notifier)
          .select(spaceId: kHomeSpaceId, roomId: _room);
      await Future<void>.delayed(Duration.zero);

      expect(sink.cancelled, [_room]);
    });

    test('stays quiet in the room being read', () async {
      container
          .read(selectedRoomIdsProvider.notifier)
          .select(spaceId: kHomeSpaceId, roomId: _room);
      focused = true;

      await deliver(_message(room, 'hi'));

      expect(sink.shown, isEmpty);
    });
  });
}

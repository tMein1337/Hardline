// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/chat/composer_target.dart';
import 'package:matrix/matrix.dart' hide Visibility;

import '../support/fake_matrix.dart';

const _a = '!a:example.org';
const _b = '!b:example.org';

Event _message(Room room, String id, {String sender = '@alice:example.org'}) =>
    Event(
      content: {'msgtype': MessageTypes.Text, 'body': 'hello'},
      type: EventTypes.Message,
      eventId: id,
      senderId: sender,
      originServerTs: DateTime(2026),
      room: room,
    );

void main() {
  late FakeMatrixClient client;
  late ProviderContainer container;
  late Room roomA;
  late Room roomB;

  setUp(() {
    client = FakeMatrixClient();
    roomA = client.addRoom(_a);
    roomB = client.addRoom(_b);
    container = ProviderContainer();
  });

  tearDown(() => container.dispose());

  ComposerTargets targets() => container.read(composerTargetsProvider.notifier);

  test('a reply belongs to the room of the message it answers', () {
    targets().replyTo(_message(roomA, r'$1'));

    final target = container.read(composerTargetProvider(_a));
    expect(target, isA<ReplyTarget>());
    expect(target!.event.eventId, r'$1');
    expect(container.read(composerTargetProvider(_b)), isNull);
  });

  test('choosing another message replaces the reply', () {
    targets().replyTo(_message(roomA, r'$1'));
    targets().replyTo(_message(roomA, r'$2'));

    expect(container.read(composerTargetProvider(_a))!.event.eventId, r'$2');
  });

  test('editing replaces a reply in the same room', () {
    targets().replyTo(_message(roomA, r'$1'));
    targets().edit(_message(roomA, r'$2', sender: client.me), text: 'hello');

    final target = container.read(composerTargetProvider(_a));
    expect(target, isA<EditTarget>());
    expect((target! as EditTarget).text, 'hello');
  });

  test('clearing one room leaves the others alone', () {
    targets().replyTo(_message(roomA, r'$1'));
    targets().replyTo(_message(roomB, r'$2'));

    targets().clear(_a);

    expect(container.read(composerTargetProvider(_a)), isNull);
    expect(container.read(composerTargetProvider(_b)), isNotNull);
  });
}

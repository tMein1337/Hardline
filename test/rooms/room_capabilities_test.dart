// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/matrix/room_capabilities.dart';
import 'package:matrix/matrix.dart';

import '../support/fake_matrix.dart';

const _me = '@me:example.org';
const _alice = '@alice:example.org';
const _mod = '@mod:example.org';
const _admin = '@admin:example.org';

void main() {
  late FakeMatrixClient client;

  setUp(() => client = FakeMatrixClient(me: _me));

  /// A room with one of each, and this account at [myLevel].
  Room roomAt(int myLevel, {Map<String, int> events = const {}}) =>
      client.addRoom(
        '!room:example.org',
        levels: {_me: myLevel, _mod: 50, _admin: 100},
        events: events,
        members: [_alice, _mod, _admin],
      );

  group('canDescribe', () {
    // The defect this file was opened for. Asked with `canSendEvent`, an
    // event type the power levels do not mention fell back to
    // `events_default` — zero — so on a homeserver that names neither the
    // name nor the topic, every member was shown two live fields and a Save
    // button the server would refuse.
    test('is false for a member when the event types are not named', () {
      expect(canDescribe(roomAt(0)), isFalse);
    });

    test('is true for a moderator in the same room', () {
      expect(canDescribe(roomAt(50)), isTrue);
    });

    test('follows a room that lets members rename it', () {
      final room = roomAt(0, events: {'m.room.name': 0, 'm.room.topic': 0});
      expect(canDescribe(room), isTrue);
    });

    // Both, or neither. A pane where the name is live and the topic is not
    // raises more questions than it answers.
    test('needs both the name and the topic', () {
      final room = roomAt(0, events: {'m.room.name': 0});
      expect(canDescribe(room), isFalse);
    });

    test('is false in a room this account has left', () {
      final room = client.addRoom(
        '!left:example.org',
        levels: {_me: 100},
        membership: Membership.leave,
      );
      expect(canDescribe(room), isFalse);
    });
  });

  group('canDismantle', () {
    test('needs the power to release a space\'s rooms, not just to kick', () {
      // Kicking at 0, state at the default 50: can empty it, cannot release
      // what it lists. Halfway is worse than not starting.
      final space = client.addRoom(
        '!space:example.org',
        space: true,
        levels: {_me: 0},
        powerLevels: {'kick': 0},
      );
      expect(canDismantle(space), isFalse);
    });

    test('is offered to somebody who can do both', () {
      final space = client.addRoom(
        '!space:example.org',
        space: true,
        levels: {_me: 50},
      );
      expect(canDismantle(space), isTrue);
    });
  });

  group('the settings', () {
    test('a member can change none of them', () {
      final room = roomAt(0);
      expect(canSetAvatar(room), isFalse);
      expect(canChangeAccess(room), isFalse);
      expect(canChangeHistory(room), isFalse);
      expect(canPublish(room), isFalse);
      expect(canChangePermissions(room), isFalse);
    });

    test('each follows its own event type', () {
      // The shape of a Synapse room: a moderator can change the picture and
      // who may join, and not who can read the history or the permissions.
      final room = roomAt(
        50,
        events: {'m.room.history_visibility': 100, 'm.room.power_levels': 100},
      );
      expect(canSetAvatar(room), isTrue);
      expect(canChangeAccess(room), isTrue);
      expect(canPublish(room), isTrue);
      expect(canChangeHistory(room), isFalse);
      expect(canChangePermissions(room), isFalse);
    });
  });

  group('removing somebody', () {
    test('a member can remove nobody', () {
      final room = roomAt(0);
      expect(canKickMember(room, _alice), isFalse);
      expect(canBanMember(room, _alice), isFalse);
    });

    // The rule that surprises people: strictly below, however the room is
    // configured. A moderator cannot remove another moderator.
    test('a moderator can remove a member and not a moderator', () {
      final room = roomAt(50);
      expect(canKickMember(room, _alice), isTrue);
      expect(canBanMember(room, _alice), isTrue);
      expect(canKickMember(room, _mod), isFalse);
      expect(canBanMember(room, _mod), isFalse);
      expect(canKickMember(room, _admin), isFalse);
    });

    test('nobody can remove themselves this way', () {
      final room = roomAt(100);
      expect(canKickMember(room, _me), isFalse);
      expect(canBanMember(room, _me), isFalse);
    });

    test('an invitation can be withdrawn like a membership', () {
      final room = roomAt(50);
      client.member(
        room.id,
        '@guest:example.org',
        membership: Membership.invite,
      );
      expect(canKickMember(room, '@guest:example.org'), isTrue);
    });

    // Somebody who has left is not there to be removed — but can still be
    // kept out, which is what a ban is for.
    test('somebody who left can be banned and not removed', () {
      final room = roomAt(50);
      client.member(room.id, _alice, membership: Membership.leave);
      expect(canKickMember(room, _alice), isFalse);
      expect(canBanMember(room, _alice), isTrue);
    });

    test('somebody already banned is not offered a second ban', () {
      final room = roomAt(50);
      client.member(room.id, _alice, membership: Membership.ban);
      expect(canBanMember(room, _alice), isFalse);
      expect(canUnbanMember(room, _alice), isTrue);
    });

    // Lifting a ban is a change of membership to `leave`, which is what a
    // kick is, and the authorisation rules check it as both.
    test('lifting a ban needs the level for banning and for removing', () {
      final room = client.addRoom(
        '!strict:example.org',
        levels: {_me: 50},
        powerLevels: {'ban': 50, 'kick': 100},
        members: [_alice],
      );
      client.member(room.id, _alice, membership: Membership.ban);
      expect(canUnbanMember(room, _alice), isFalse);
    });

    test('only a ban can be lifted', () {
      final room = roomAt(100);
      expect(canUnbanMember(room, _alice), isFalse);
    });
  });

  group('canSetLevel', () {
    test('needs the power to edit power levels at all', () {
      final room = roomAt(50, events: {'m.room.power_levels': 100});
      expect(canSetLevel(room, _alice, 50), isFalse);
    });

    test('an admin can raise a member as far as admin', () {
      final room = roomAt(100);
      expect(canSetLevel(room, _alice, 50), isTrue);
      expect(canSetLevel(room, _alice, 100), isTrue);
    });

    // Otherwise a moderator allowed to edit the event could write themselves
    // into it at any level they liked.
    test('nobody can be raised above the person doing it', () {
      final room = roomAt(50, events: {'m.room.power_levels': 50});
      expect(canSetLevel(room, _alice, 50), isTrue);
      expect(canSetLevel(room, _alice, 100), isFalse);
    });

    test('somebody at or above cannot be touched', () {
      final room = roomAt(50, events: {'m.room.power_levels': 50});
      expect(canSetLevel(room, _mod, 0), isFalse);
      expect(canSetLevel(room, _admin, 0), isFalse);
    });

    // Stepping down is always permitted. Stepping up is not something
    // anybody can do for themselves.
    test('you can lower yourself and not raise yourself', () {
      final room = roomAt(50, events: {'m.room.power_levels': 50});
      expect(canSetLevel(room, _me, 0), isTrue);
      expect(canSetLevel(room, _me, 50), isTrue);
      expect(canSetLevel(room, _me, 100), isFalse);
    });

    // From room version 12 the creator outranks every number, including
    // somebody else's 100.
    test('a creator in a version 12 room is out of an admin\'s reach', () {
      final room = client.addRoom(
        '!v12:example.org',
        version: '12',
        creator: '@founder:example.org',
        levels: {_me: 100},
        members: ['@founder:example.org'],
      );
      expect(canSetLevel(room, '@founder:example.org', 0), isFalse);
      expect(canKickMember(room, '@founder:example.org'), isFalse);
    });
  });

  group('a space\'s rooms', () {
    test('adding and removing are the same permission', () {
      final space = client.addRoom(
        '!space:example.org',
        space: true,
        levels: {_me: 50},
      );
      expect(canAddToSpace(space), isTrue);
      expect(canRemoveFromSpace(space), isTrue);
    });

    test('a member of the space can do neither', () {
      final space = client.addRoom('!space:example.org', space: true);
      expect(canAddToSpace(space), isFalse);
      expect(canRemoveFromSpace(space), isFalse);
    });

    test('a room is not a space', () {
      expect(canRemoveFromSpace(roomAt(100)), isFalse);
    });
  });
}

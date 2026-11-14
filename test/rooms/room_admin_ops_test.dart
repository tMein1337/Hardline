// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/matrix/room_permissions.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/rooms/room_admin.dart';
import 'package:hardline/features/rooms/room_members.dart';
import 'package:matrix/matrix.dart';

import '../support/fake_matrix.dart';

const _me = '@me:example.org';
const _alice = '@alice:example.org';
const _bob = '@bob:example.org';
const _room = '!room:example.org';
const _space = '!space:example.org';

void main() {
  late FakeMatrixClient client;
  late ProviderContainer container;
  late RoomAdmin admin;

  setUp(() {
    client = FakeMatrixClient(me: _me);
    container = ProviderContainer(
      overrides: [clientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    admin = container.read(roomAdminProvider);
  });

  /// Recomputed each time, as the sync tick would have it in the app.
  RoomAdminInfo info([String roomId = _room]) {
    container.invalidate(roomAdminInfoProvider(roomId));
    return container.read(roomAdminInfoProvider(roomId))!;
  }

  group('what is sent', () {
    setUp(() {
      client.addRoom(
        _room,
        name: 'Room',
        levels: {_me: 100},
        members: [_alice],
      );
    });

    test('removing, banning and lifting a ban', () async {
      await admin.kick(_room, _alice);
      await admin.ban(_room, _alice);
      await admin.unban(_room, _alice);
      expect(client.calls, [
        'kick $_room $_alice',
        'ban $_room $_alice',
        'unban $_room $_alice',
      ]);
    });

    test('a role is one write to the power levels', () async {
      await admin.setLevel(_room, _alice, 50);
      expect(client.calls, ['state $_room m.room.power_levels']);
      expect(
        client.getRoomById(_room)!.getPowerLevelByUserId(_alice).level,
        50,
      );
      // And nobody else moved.
      expect(client.getRoomById(_room)!.ownPowerLevel.level, 100);
    });

    test('a permission keeps everything else in the event', () async {
      await admin.setPermission(_room, RoomPermission.invite, 50);
      final content = client
          .getRoomById(_room)!
          .getState(EventTypes.RoomPowerLevels)!
          .content;
      expect(content['invite'], 50);
      expect(content['kick'], 50);
      expect(content['users'], {_me: 100});
    });

    test('who can join, and who can read', () async {
      await admin.setAccess(_room, RoomAccess.public);
      await admin.setHistory(_room, HistoryVisibility.joined);
      expect(info().joinRule, JoinRules.public);
      expect(info().history, HistoryVisibility.joined);
    });

    // The rule is written into the room and names the spaces by id.
    test('restricting to a space names the space', () async {
      await admin.setAccess(
        _room,
        RoomAccess.spaceMembers,
        throughSpaceIds: [_space],
      );
      final content = client
          .getRoomById(_room)!
          .getState(EventTypes.RoomJoinRules)!
          .content;
      expect(content['join_rule'], 'restricted');
      expect(content['allow'], [
        {'room_id': _space, 'type': 'm.room_membership'},
      ]);
    });

    test('the directory is asked and told', () async {
      expect(await admin.isListed(_room), isFalse);
      await admin.setListed(_room, true);
      expect(await admin.isListed(_room), isTrue);
      await admin.setListed(_room, false);
      expect(await admin.isListed(_room), isFalse);
    });

    test('a picture is uploaded and then set', () async {
      await admin.setAvatar(
        _room,
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'cat.png',
      );
      expect(client.calls, ['upload cat.png 3b', 'state $_room m.room.avatar']);
      expect(info().avatarMxc, startsWith('mxc://'));

      await admin.removeAvatar(_room);
      expect(info().avatarMxc, isNull);
    });
  });

  // A room that has never had a power-levels event has an implicit one in
  // which its creator is at 100. Writing the first explicit one replaces
  // that wholesale, so an event carrying only the field being changed would
  // put everybody at zero — the person writing it included, for good.
  test('the first power-levels event keeps its author in charge', () async {
    client.addRoom(_room, creator: _me, withPowerLevels: false);
    expect(client.getRoomById(_room)!.ownPowerLevel.level, 100);

    await admin.setPermission(_room, RoomPermission.invite, 50);

    expect(client.getRoomById(_room)!.ownPowerLevel.level, 100);
  });

  group('taking a room out of a space', () {
    setUp(() {
      client.addRoom(_space, name: 'Space', space: true, levels: {_me: 50});
      client.addRoom(_room, name: 'Room', members: [_alice]);
      client.child(_space, _room);
    });

    test('writes to the space and leaves the room alone', () async {
      expect(info().parents.single.name, 'Space');

      await admin.removeFromSpace(_space, _room);

      expect(client.calls, ['state $_space m.space.child $_room']);
      expect(info().parents, isEmpty);
      // Still in it, and so is everybody else.
      expect(client.getRoomById(_room)!.membership, Membership.join);
      expect(client.calls.any((call) => call.startsWith('kick')), isFalse);
    });

    // It is a write to the space, so the space is where the power is needed.
    test('is offered by power in the space, not in the room', () {
      expect(info().parents.single.canRemove, isTrue);
      expect(info().canDescribe, isFalse, reason: 'no power in the room');
    });

    test('is not offered to somebody who merely belongs to the space', () {
      client.state(_space, EventTypes.RoomPowerLevels, {
        'users': {_me: 0},
        'state_default': 50,
      });
      expect(info().parents.single.canRemove, isFalse);
    });
  });

  group('a parent the room names', () {
    // `setSpaceChild` has always written an `m.space.parent` beside the
    // child event, and nothing read them.
    test('is reported when this account is not in that space', () {
      client.addRoom(_room, name: 'Room');
      client.state(_room, EventTypes.SpaceParent, {
        'via': ['other.org'],
      }, stateKey: '!elsewhere:other.org');

      final claimed = info().claimedParents.single;
      expect(claimed.id, '!elsewhere:other.org');
      expect(claimed.via, ['other.org']);
    });

    test('is not reported twice for a space already joined', () {
      client.addRoom(_space, name: 'Space', space: true);
      client.addRoom(_room, name: 'Room');
      client.child(_space, _room);
      client.state(_room, EventTypes.SpaceParent, {
        'via': ['example.org'],
      }, stateKey: _space);

      expect(info().parents, hasLength(1));
      expect(info().claimedParents, isEmpty);
    });

    // Removing a parent link is writing it empty, which is not a claim.
    test('an emptied link is not a claim', () {
      client.addRoom(_room, name: 'Room');
      client.state(_room, EventTypes.SpaceParent, {}, stateKey: '!gone:x');
      expect(info().claimedParents, isEmpty);
    });
  });

  group('what the dialog is told', () {
    test('"anyone in its space" needs a space and a room version with it', () {
      client.addRoom(_space, space: true);
      client.addRoom(_room, version: '10');
      expect(info().canRestrictToSpace, isFalse, reason: 'no space yet');

      client.child(_space, _room);
      expect(info().canRestrictToSpace, isTrue);

      client.addRoom('!old:x', version: '6');
      client.child(_space, '!old:x');
      expect(info('!old:x').canRestrictToSpace, isFalse);
    });

    test('a permission above this account\'s role is out of reach', () {
      client.addRoom(
        _room,
        levels: {_me: 50},
        events: {'m.room.power_levels': 50},
        powerLevels: {'ban': 100},
      );
      final room = info();
      expect(room.canSetPermission(RoomPermission.kick, 50), isTrue);
      expect(room.canSetPermission(RoomPermission.kick, 0), isTrue);
      // Cannot be set above their own role…
      expect(room.canSetPermission(RoomPermission.kick, 100), isFalse);
      // …and one already above it cannot be touched at all.
      expect(room.canSetPermission(RoomPermission.ban, 50), isFalse);
    });

    test('only the permissions that apply are listed', () {
      client.addRoom(_room);
      client.addRoom(_space, space: true);
      expect(info().permissions.keys, contains(RoomPermission.calls));
      expect(
        info().permissions.keys,
        isNot(contains(RoomPermission.manageRooms)),
      );
      expect(
        info(_space).permissions.keys,
        contains(RoomPermission.manageRooms),
      );
      expect(
        info(_space).permissions.keys,
        isNot(contains(RoomPermission.calls)),
      );
    });
  });

  group('the member list', () {
    RoomMemberList members() {
      container.invalidate(roomMembersProvider(_room));
      return container.read(roomMembersProvider(_room));
    }

    setUp(() {
      client.addRoom(
        _room,
        levels: {_me: 50, _bob: 100},
        // As Synapse makes them: a moderator cannot edit the power levels.
        events: {'m.room.power_levels': 100},
        members: [_alice, _bob],
      );
    });

    test('is ordered by standing, then role, then name', () {
      client.member(_room, '@zed:example.org', membership: Membership.invite);
      client.member(_room, '@troll:example.org', membership: Membership.ban);

      expect(members().members.map((m) => m.userId), [
        _bob,
        _me,
        _alice,
        '@zed:example.org',
        '@troll:example.org',
      ]);
    });

    // A room's history holds everybody who ever passed through, and a member
    // list is not that.
    test('leaves out people who have left', () {
      client.member(_room, _alice, membership: Membership.leave);
      expect(members().members.map((m) => m.userId), [_bob, _me]);
    });

    test('offers only what the server would accept', () {
      final byId = {for (final m in members().members) m.userId: m};

      expect(byId[_alice]!.canKick, isTrue);
      expect(byId[_alice]!.canBan, isTrue);
      // No power-level rights at 50 in this room, so no roles to give.
      expect(byId[_alice]!.grantable, isEmpty);

      // Above this account: nothing at all.
      expect(byId[_bob]!.hasActions, isFalse);
      expect(byId[_me]!.isSelf, isTrue);
      expect(byId[_me]!.canKick, isFalse);
    });

    test('an admin is offered the roles somebody does not already hold', () {
      client.state(_room, EventTypes.RoomPowerLevels, {
        'users': {_me: 100},
        'state_default': 50,
      });
      final alice = members().members.firstWhere((m) => m.userId == _alice);
      expect(alice.grantable, [RoomRole.moderator, RoomRole.admin]);
    });

    // Lazy loading: the room holds only who has spoken lately. Somebody who
    // joined a year ago and never said a word is exactly who a member list
    // is for.
    test('fetches the people sync never delivered', () async {
      client.unloadedMembers[_room] = [
        FakeMatrixClient.memberEvent(
          '@quiet:example.org',
          displayName: 'Quiet',
        ),
        FakeMatrixClient.memberEvent(
          '@troll:example.org',
          membership: Membership.ban,
        ),
      ];
      expect(members().members, hasLength(3));

      await container.read(roomMembersLoadProvider(_room).future);

      expect(client.calls, ['members $_room']);
      final ids = members().members.map((m) => m.userId);
      expect(ids, contains('@quiet:example.org'));
      expect(ids, contains('@troll:example.org'));
    });

    test('a removal shows up without fetching again', () async {
      await container.read(roomMembersLoadProvider(_room).future);
      client.calls.clear();

      await admin.kick(_room, _alice);
      // What `matrixTickProvider` does on the next sync.
      container.invalidate(roomMembersProvider(_room));

      expect(members().members.map((m) => m.userId), isNot(contains(_alice)));
      expect(client.calls, ['kick $_room $_alice']);
    });

    test('searches names and ids, ignoring case', () {
      client.member(_room, _alice, displayName: 'Alice Liddell');
      expect(members().matching('LIDD').members.single.userId, _alice);
      expect(members().matching('bob:ex').members.single.userId, _bob);
      expect(members().matching('nobody').members, isEmpty);
      expect(members().matching('  ').members, hasLength(3));
    });
  });

  group('who can be offered for an invitation', () {
    setUp(() {
      client.addRoom(_room);
      client.addRoom('!other:x', members: [_alice, _bob]);
      client.member('!other:x', _alice, displayName: 'Alice');
      client.member('!other:x', _bob, displayName: 'Bob');
    });

    List<String> offered(String query) => [
      for (final person in invitableMatching(
        client,
        roomId: _room,
        query: query,
      ))
        person.userId,
    ];

    test('people from other rooms, by name or by id', () {
      expect(offered('ali'), [_alice]);
      expect(offered('@bob'), [_bob]);
      expect(offered('example.org'), [_alice, _bob]);
    });

    test('nobody until something is typed', () {
      expect(offered(''), isEmpty);
      expect(offered('   '), isEmpty);
    });

    test('never this account', () {
      expect(offered('me'), isEmpty);
    });

    // The first two would fail. The third should be a decision somebody
    // makes on the member list, not a name that autocompletes.
    test('nobody already here, invited, or banned', () {
      client.member(_room, _alice);
      expect(offered('example.org'), [_bob]);
      client.member(_room, _bob, membership: Membership.invite);
      expect(offered('example.org'), isEmpty);
      client.member(_room, _bob, membership: Membership.ban);
      expect(offered('example.org'), isEmpty);
      // Somebody who left can be asked back.
      client.member(_room, _bob, membership: Membership.leave);
      expect(offered('example.org'), [_bob]);
    });

    test('a name that starts with the text comes first', () {
      client.member('!other:x', '@zalice:example.org', displayName: 'Xalia');
      client.member('!other:x', _alice, displayName: 'Alia');
      expect(offered('ali').first, _alice);
    });
  });
}

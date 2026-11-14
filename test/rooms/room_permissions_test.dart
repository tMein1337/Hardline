// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/matrix/room_permissions.dart';

/// What Synapse writes into a freshly made room. Not every homeserver's
/// defaults, which is the point of several tests below.
const _synapse = <String, Object?>{
  'users': {'@creator:example.org': 100},
  'users_default': 0,
  'events': {
    'm.room.name': 50,
    'm.room.power_levels': 100,
    'm.room.history_visibility': 100,
    'm.room.canonical_alias': 50,
    'm.room.avatar': 50,
    'm.room.tombstone': 100,
    'm.room.server_acl': 100,
    'm.room.encryption': 100,
  },
  'events_default': 0,
  'state_default': 50,
  'ban': 50,
  'kick': 50,
  'redact': 50,
  'invite': 0,
};

void main() {
  group('roleLabel', () {
    test('names the three conventional levels', () {
      expect(roleLabel(0), 'Member');
      expect(roleLabel(50), 'Moderator');
      expect(roleLabel(100), 'Admin');
    });

    // Rounding to the nearest name would hide the one fact that explains why
    // a moderator at 50 cannot remove somebody at 60.
    test('does not round a level in between', () {
      expect(roleLabel(60), 'Custom (60)');
      expect(roleLabel(25), 'Custom (25)');
      expect(roleLabel(101), 'Admin (101)');
      expect(roleLabel(-1), 'Restricted (-1)');
    });

    // Room version 12 puts the creator above every number, and the SDK
    // represents that as the largest integer JSON can hold.
    test('does not print the number that stands for a creator', () {
      expect(roleLabel(kCreatorLevel), 'Creator');
    });
  });

  group('requiredLevel', () {
    test('reads a field the event states', () {
      expect(requiredLevel(_synapse, RoomPermission.kick), 50);
      expect(requiredLevel(_synapse, RoomPermission.invite), 0);
      expect(requiredLevel(_synapse, RoomPermission.sendMessages), 0);
      expect(requiredLevel(_synapse, RoomPermission.permissions), 100);
    });

    // The mistake `canDescribe` used to make. Synapse names `m.room.name`
    // and not `m.room.topic`; the topic is a state event, so it needs
    // `state_default` — 50 — and not the `events_default` of 0 that an
    // ordinary message would.
    test('falls back to state_default for a state event, not to 0', () {
      final onlyName = {
        ..._synapse,
        'events': {'m.room.name': 0},
      };
      expect(requiredLevel(onlyName, RoomPermission.describe), 50);

      final nothingNamed = {..._synapse, 'events': <String, Object?>{}};
      expect(requiredLevel(nothingNamed, RoomPermission.describe), 50);
      expect(requiredLevel(nothingNamed, RoomPermission.calls), 50);
      expect(requiredLevel(nothingNamed, RoomPermission.manageRooms), 50);
    });

    // Three event types behind one row. Saying "members can" about a room
    // where they can change the topic and not the name would be a control
    // that fails for two thirds of what it claims to cover.
    test('reports the highest of several event types', () {
      final mixed = {
        ..._synapse,
        'events': {'m.room.name': 100, 'm.room.topic': 0, 'm.room.avatar': 50},
      };
      expect(requiredLevel(mixed, RoomPermission.describe), 100);
    });

    test('uses the specified defaults for a field the event omits', () {
      const sparse = <String, Object?>{'users': <String, Object?>{}};
      expect(requiredLevel(sparse, RoomPermission.kick), 50);
      expect(requiredLevel(sparse, RoomPermission.ban), 50);
      expect(requiredLevel(sparse, RoomPermission.redact), 50);
      expect(requiredLevel(sparse, RoomPermission.invite), 0);
      expect(requiredLevel(sparse, RoomPermission.settings), 50);
    });

    // With no event at all the creator is implicitly at 100 and changing the
    // room needs nothing. Different from an event that merely omits the
    // field, and the difference is in the specification.
    test('treats a room with no power-levels event differently', () {
      expect(requiredLevel(null, RoomPermission.settings), 0);
      expect(requiredLevel(null, RoomPermission.describe), 0);
      expect(requiredLevel(null, RoomPermission.kick), 50);
    });

    test('ignores a value that is not a number', () {
      final broken = {..._synapse, 'kick': 'fifty'};
      expect(requiredLevel(broken, RoomPermission.kick), 50);
    });
  });

  group('withRequiredLevel', () {
    test('changes the one thing asked', () {
      final next = withRequiredLevel(_synapse, RoomPermission.invite, 50);
      expect(next['invite'], 50);
      expect(next['kick'], 50);
      expect(requiredLevel(next, RoomPermission.invite), 50);
    });

    // The event may carry levels for event types this app has no name for,
    // set by another client. Rebuilding it from the parts understood here
    // would silently reset every one of them.
    test('carries over everything it does not understand', () {
      final withExtras = {
        ..._synapse,
        'notifications': {'room': 50},
        'io.example.custom': 'kept',
        'events': {
          ...(_synapse['events']! as Map<String, Object?>),
          'io.example.widget': 75,
        },
      };

      final next = withRequiredLevel(withExtras, RoomPermission.kick, 100);

      expect(next['notifications'], {'room': 50});
      expect(next['io.example.custom'], 'kept');
      expect((next['events']! as Map)['io.example.widget'], 75);
      expect(next['users'], {'@creator:example.org': 100});
    });

    // The map handed in belongs to a state event the SDK is still holding.
    // Writing through it would change what the room believes before the
    // homeserver has agreed to anything.
    test('does not modify what it was given', () {
      final events = <String, Object?>{'m.room.name': 50};
      final original = <String, Object?>{'kick': 50, 'events': events};

      withRequiredLevel(original, RoomPermission.kick, 100);
      withRequiredLevel(original, RoomPermission.describe, 100);

      expect(original['kick'], 50);
      expect(events, {'m.room.name': 50});
    });

    test('writes every event type a permission covers', () {
      final next = withRequiredLevel(_synapse, RoomPermission.describe, 100);
      final events = next['events']! as Map;
      expect(events['m.room.name'], 100);
      expect(events['m.room.topic'], 100);
      expect(events['m.room.avatar'], 100);
      // And leaves its neighbours alone.
      expect(events['m.room.power_levels'], 100);
      expect(events['m.room.canonical_alias'], 50);
    });

    test('starts an events map when there was none', () {
      final next = withRequiredLevel(
        const {'kick': 50},
        RoomPermission.calls,
        0,
      );
      expect(next['events'], {'org.matrix.msc3401.call.member': 0});
    });

    test('does not invent an events map for a plain field', () {
      final next = withRequiredLevel(
        const {'kick': 50},
        RoomPermission.ban,
        100,
      );
      expect(next.containsKey('events'), isFalse);
    });

    test('round-trips through requiredLevel for every permission', () {
      for (final permission in RoomPermission.values) {
        for (final role in RoomRole.values) {
          final next = withRequiredLevel(_synapse, permission, role.level);
          expect(
            requiredLevel(next, permission),
            role.level,
            reason: '${permission.name} -> ${role.label}',
          );
        }
      }
    });
  });

  group('which permissions apply', () {
    // A space holds no conversation and no call; a room has no children.
    test('a space is not offered calls, and a room is not offered rooms', () {
      expect(RoomPermission.calls.appliesTo(isSpace: true), isFalse);
      expect(RoomPermission.calls.appliesTo(isSpace: false), isTrue);
      expect(RoomPermission.manageRooms.appliesTo(isSpace: true), isTrue);
      expect(RoomPermission.manageRooms.appliesTo(isSpace: false), isFalse);
      expect(RoomPermission.kick.appliesTo(isSpace: true), isTrue);
      expect(RoomPermission.kick.appliesTo(isSpace: false), isTrue);
    });
  });
}

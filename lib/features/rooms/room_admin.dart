// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/room_capabilities.dart' as capabilities;
import '../../core/matrix/space_children.dart';
import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/display_name.dart';

/// One step of taking a space apart, so the dialog can say where it got to.
enum DismantleStep {
  detaching('Detaching it'),
  removingAddress('Removing the address'),
  removingMembers('Removing the other members'),
  leaving('Leaving');

  const DismantleStep(this.label);

  final String label;
}

/// Changing and dismantling a space.
///
/// Separate from the dialog because the destructive path is several requests
/// that each partly succeed, and that is worth reading in one place rather
/// than interleaved with widgets.
class RoomAdmin {
  const RoomAdmin(this._client);

  final Client _client;

  Room _require(String roomId) {
    final room = _client.getRoomById(roomId);
    if (room == null) throw StateError('That space is no longer here.');
    return room;
  }

  Future<void> rename(String roomId, String name) async {
    await _client.setRoomStateWithKey(roomId, EventTypes.RoomName, '', {
      'name': name,
    });
  }

  Future<void> setTopic(String roomId, String topic) async {
    await _client.setRoomStateWithKey(roomId, EventTypes.RoomTopic, '', {
      'topic': topic,
    });
  }

  /// Leaves without touching anything else.
  ///
  /// The space carries on existing for everybody else, which is the whole
  /// difference between this and [dismantle].
  Future<void> leave(String roomId) async {
    final room = _require(roomId);
    await room.leave();
    // Forgotten as well, so it does not sit in the account as a room this
    // client has left. Leaving without forgetting is how a space you walked
    // out of comes back on the next fresh sync.
    await room.forget();
  }

  /// Takes a room or a space apart, as far as Matrix allows.
  ///
  /// **This is not a delete, and cannot be.** There is no way to erase a room
  /// from a homeserver over the client API — the events exist on every server
  /// that has ever seen them, and no client of any kind can reach back and
  /// remove them. What this does is everything that *is* reachable, in the
  /// order that makes each step survivable if the next one fails:
  ///
  ///  1. **Detach it from the space graph**, in whichever direction it has
  ///     edges. A space releases its children — they are not touched
  ///     otherwise, because deleting a space must never delete the
  ///     conversations in it, and anybody in one keeps it in their Home list.
  ///     A room is removed from whatever space contains it, so it stops
  ///     appearing in a list it can no longer be opened from.
  ///
  ///     Detaching a room from its parent needs power *in the parent*, which
  ///     is a different room and a permission this account may not have. It is
  ///     attempted and reported rather than required: a room can be dismantled
  ///     perfectly well while remaining listed in somebody else's space, and
  ///     refusing to start would be worse than saying so afterwards.
  ///  2. **Remove the address**, so nobody can find or join it by alias. The
  ///     directory entry goes with it.
  ///  3. **Remove the other members**, so nobody is left inside something the
  ///     person who ran it considers gone.
  ///  4. **Leave and forget**, last, because every step above needs the power
  ///     level that leaving gives up.
  ///
  /// Reports each step as it starts so a slow dismantle says what it is doing.
  /// Individual failures within a step are collected rather than thrown: a
  /// member who cannot be kicked should not leave the space half-dismantled
  /// with its rooms already released.
  Future<List<String>> dismantle(
    String roomId, {
    void Function(DismantleStep step)? onStep,
  }) async {
    final room = _require(roomId);
    final problems = <String>[];

    onStep?.call(DismantleStep.detaching);
    if (room.isSpace) {
      for (final childId in childRoomIdsOf(room)) {
        try {
          await room.removeSpaceChild(childId);
        } catch (error) {
          problems.add('Could not release $childId: ${_short(error)}');
        }
      }
    } else {
      for (final parent in _parentsOf(roomId)) {
        try {
          await parent.removeSpaceChild(roomId);
        } catch (error) {
          problems.add(
            'Could not remove it from ${parent.getLocalizedDisplayname()}: '
            '${_short(error)}',
          );
        }
      }
    }

    onStep?.call(DismantleStep.removingAddress);
    final alias = room.canonicalAlias;
    if (alias.isNotEmpty) {
      try {
        // The state event first: it is what other clients read, and it is the
        // half this account can always change. The directory entry is the
        // server's, and deleting it can be refused independently.
        await _client.setRoomStateWithKey(
          roomId,
          EventTypes.RoomCanonicalAlias,
          '',
          const {},
        );
        await _client.deleteRoomAlias(alias);
      } catch (error) {
        problems.add('Could not remove the address $alias: ${_short(error)}');
      }
    }
    try {
      await _client.setRoomVisibilityOnDirectory(
        roomId,
        visibility: Visibility.private,
      );
    } catch (_) {
      // Frequently refused for a room that was never published, and saying so
      // would be noise about something that was already true.
    }

    onStep?.call(DismantleStep.removingMembers);
    final ownId = _client.userID;
    for (final member in room.getParticipants(const [Membership.join])) {
      if (member.id == ownId) continue;
      try {
        await room.kick(member.id);
      } catch (error) {
        problems.add('Could not remove ${member.id}: ${_short(error)}');
      }
    }

    onStep?.call(DismantleStep.leaving);
    await room.leave();
    await room.forget();

    return problems;
  }

  /// Every space this account can see that lists [roomId] as a child.
  ///
  /// Plural because nothing stops a room being in several, and removing it
  /// from one while leaving it in another would be a half-measure that looks
  /// like a bug.
  List<Room> _parentsOf(String roomId) => [
    for (final room in _client.rooms)
      if (room.isSpace &&
          room.membership == Membership.join &&
          childRoomIdsOf(room).contains(roomId))
        room,
  ];

  static String _short(Object error) {
    final text = error.toString();
    return text.length > 120 ? '${text.substring(0, 117)}…' : text;
  }
}

final roomAdminProvider = Provider<RoomAdmin>(
  (ref) => RoomAdmin(ref.watch(clientProvider)),
);

/// What a space looks like to the manage dialog.
///
/// A snapshot rather than the `Room`, for the reason everything else in this
/// app takes one: the SDK mutates its objects in place.
@immutable
class RoomAdminInfo {
  const RoomAdminInfo({
    required this.name,
    required this.topic,
    required this.alias,
    required this.avatarMxc,
    required this.memberCount,
    required this.childCount,
    required this.isSpace,
    required this.isDirect,
    required this.directUserId,
    required this.isEncrypted,
    required this.parentNames,
    required this.canDescribe,
    required this.canInvite,
    required this.canDismantle,
  });

  final String name;
  final String topic;

  /// Empty when the space has no published address.
  final String alias;

  final String? avatarMxc;
  final int memberCount;

  /// Rooms inside it. Always zero for a room, which is not a container.
  final int childCount;

  final bool isSpace;

  /// A direct chat, which is a room that is really a person.
  ///
  /// Renaming one, or giving it a topic, is possible and almost never what
  /// anybody means — so the dialog offers the person instead.
  final bool isDirect;

  final String? directUserId;
  final bool isEncrypted;

  /// The spaces this room is filed under, by name.
  ///
  /// Shown before something destructive, because being in a space is the part
  /// people forget: leaving a room that a space lists still leaves it listed,
  /// for everybody who can see that space.
  final List<String> parentNames;

  final bool canDescribe;
  final bool canInvite;
  final bool canDismantle;
}

/// What the manage dialog shows for one space.
///
/// Recomputed on the sync tick, so renaming it from another client — or from
/// this one — updates the dialog while it is open.
final roomAdminInfoProvider = Provider.family<RoomAdminInfo?, String>((
  ref,
  roomId,
) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);
  final space = client.getRoomById(roomId);
  if (space == null) return null;

  return RoomAdminInfo(
    name: displaySafeName(space.getLocalizedDisplayname()),
    topic: space.topic,
    alias: space.canonicalAlias,
    avatarMxc: space.avatar?.toString(),
    // `getParticipants` reads loaded members only, so this is "as far as this
    // client knows" rather than the server's count. Honest enough for a line
    // that exists to give a sense of scale before something destructive.
    memberCount: space.getParticipants(const [Membership.join]).length,
    childCount: space.isSpace ? childRoomIdsOf(space).length : 0,
    isSpace: space.isSpace,
    isDirect: space.isDirectChat,
    directUserId: space.directChatMatrixID,
    isEncrypted: space.encrypted,
    parentNames: [
      for (final parent in client.rooms)
        if (parent.isSpace &&
            parent.membership == Membership.join &&
            childRoomIdsOf(parent).contains(roomId))
          displaySafeName(parent.getLocalizedDisplayname()),
    ],
    canDescribe: capabilities.canDescribe(space),
    canInvite: capabilities.canInvite(space),
    canDismantle: capabilities.canDismantle(space),
  );
});

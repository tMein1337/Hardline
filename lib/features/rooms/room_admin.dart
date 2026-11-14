// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;

import '../../core/matrix/room_capabilities.dart' as capabilities;
import '../../core/matrix/room_permissions.dart';
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

/// Who can join, in the three answers worth offering.
///
/// The join rule has six values and a fourth dimension in the `allow` list.
/// Three of them cover what somebody running a room means: only who I ask,
/// anybody who is already in the place this room belongs to, or anybody at
/// all. The rest — knocking, and the two that combine it with the others —
/// are shown for what they are when a room already has one, and not offered:
/// nothing in this client can answer a knock, and a room set to it from here
/// would be a room nobody could get into.
enum RoomAccess {
  inviteOnly(
    JoinRules.invite,
    'Invited people',
    'Somebody already in it has to invite them.',
  ),
  spaceMembers(
    JoinRules.restricted,
    'Anyone in its space',
    'Members of the space it is filed under can join without being asked.',
  ),
  public(
    JoinRules.public,
    'Anyone',
    'Anybody who has the address, on any homeserver.',
  );

  const RoomAccess(this.rule, this.label, this.detail);

  final JoinRules rule;
  final String label;
  final String detail;

  /// The option matching [rule], or null for one this app does not set.
  static RoomAccess? of(JoinRules? rule) => switch (rule) {
    JoinRules.invite || JoinRules.private => inviteOnly,
    JoinRules.restricted => spaceMembers,
    JoinRules.public => public,
    _ => null,
  };
}

/// What to call a join rule this app does not offer but may find.
String describeJoinRule(JoinRules? rule) => switch (rule) {
  JoinRules.knock => 'People ask to join, and somebody lets them in',
  JoinRules.knockRestricted =>
    'Members of its space can join; anybody else asks to',
  null => 'Not set — the homeserver treats that as invitation only',
  _ => RoomAccess.of(rule)?.label ?? rule.text,
};

/// How to say each history setting to somebody choosing between them.
///
/// The four values are named for the mechanism — `shared`, `joined` — and
/// neither word says what a person joining will see.
extension HistoryVisibilityLabel on HistoryVisibility {
  String get label => switch (this) {
    HistoryVisibility.shared => 'Everything, back to the start',
    HistoryVisibility.invited => 'From when they were invited',
    HistoryVisibility.joined => 'From when they joined',
    HistoryVisibility.worldReadable => 'Everything, without joining',
  };

  String get detail => switch (this) {
    HistoryVisibility.shared =>
      'New members can read what was said before they arrived.',
    HistoryVisibility.invited =>
      'New members see nothing from before their invitation.',
    HistoryVisibility.joined =>
      'New members see nothing from before the moment they joined.',
    HistoryVisibility.worldReadable =>
      'Anybody can read it, including people who are not in the room. '
          'Meaningless in an encrypted room, where they could not decrypt '
          'it anyway.',
  };
}

/// Changing a room or a space, and taking one apart.
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

  /// Uploads [bytes] and makes them the room's picture.
  Future<void> setAvatar(
    String roomId, {
    required Uint8List bytes,
    required String filename,
  }) async {
    await _require(roomId).setAvatar(MatrixFile(bytes: bytes, name: filename));
  }

  /// The same, from a file the user picked.
  Future<void> setAvatarFromPath(String roomId, String path) async => setAvatar(
    roomId,
    bytes: await File(path).readAsBytes(),
    filename: p.basename(path),
  );

  Future<void> removeAvatar(String roomId) async {
    await _require(roomId).setAvatar(null);
  }

  /// Changes who can join.
  ///
  /// [throughSpaceIds] only means anything for [RoomAccess.spaceMembers]: the
  /// spaces whose members may walk in. The rule is written into the room, so
  /// it names them by id and keeps working whether or not this account stays
  /// in any of them.
  Future<void> setAccess(
    String roomId,
    RoomAccess access, {
    List<String> throughSpaceIds = const [],
  }) async {
    await _require(roomId).setJoinRules(
      access.rule,
      allowConditionRoomIds: access == RoomAccess.spaceMembers
          ? throughSpaceIds
          : null,
    );
  }

  /// Changes who can read what was said before they arrived.
  Future<void> setHistory(String roomId, HistoryVisibility visibility) =>
      _require(roomId).setHistoryVisibility(visibility);

  /// Whether the room is in the homeserver's public directory.
  ///
  /// A request, unlike everything else the dialog shows: the directory is the
  /// server's and no state event in the room records it.
  Future<bool> isListed(String roomId) async =>
      await _client.getRoomVisibilityOnDirectory(roomId) == Visibility.public;

  Future<void> setListed(String roomId, bool listed) =>
      _client.setRoomVisibilityOnDirectory(
        roomId,
        visibility: listed ? Visibility.public : Visibility.private,
      );

  /// Removes somebody. They can come back if the room lets them.
  Future<void> kick(String roomId, String userId) =>
      _require(roomId).kick(userId);

  /// Removes somebody and keeps them out.
  Future<void> ban(String roomId, String userId) =>
      _require(roomId).ban(userId);

  /// Lifts a ban. It does not bring them back; they have to rejoin, or be
  /// invited.
  Future<void> unban(String roomId, String userId) =>
      _require(roomId).unban(userId);

  /// Gives [userId] the power level [level].
  Future<void> setLevel(String roomId, String userId, int level) async {
    await _require(roomId).setPower(userId, level);
  }

  /// Changes the level one kind of action needs.
  Future<void> setPermission(
    String roomId,
    RoomPermission permission,
    int level,
  ) async {
    final room = _require(roomId);
    final current = room.getState(EventTypes.RoomPowerLevels)?.content;
    final next = withRequiredLevel(current, permission, level);

    // A room that has never had a power-levels event has an implicit one in
    // which whoever created it is at 100. Writing the first explicit one
    // replaces that wholesale — so an event carrying only the field being
    // changed would put everybody at zero, the person writing it included,
    // with no way for anybody to undo it. The level this account holds is
    // written in with it.
    if (current == null) {
      final me = _client.userID;
      if (me != null) {
        next['users'] = {me: room.ownPowerLevel.level};
      }
    }

    await _client.setRoomStateWithKey(
      roomId,
      EventTypes.RoomPowerLevels,
      '',
      next,
    );
  }

  /// Takes [roomId] out of [spaceId], and leaves the room itself alone.
  ///
  /// The other direction from [leave]: the room carries on, with everybody
  /// still in it, and simply stops being listed there. It is a write to the
  /// *space*, so it is the space this account needs power in — see
  /// `canRemoveFromSpace`.
  Future<void> removeFromSpace(String spaceId, String roomId) =>
      _require(spaceId).removeSpaceChild(roomId);

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

/// Whether a room is in the homeserver's public directory.
///
/// A request, and so not part of [roomAdminInfoProvider], which is recomputed
/// on every sync. Asked once when the dialog opens and again after the switch
/// is flipped.
final roomListedProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, roomId) => ref.watch(roomAdminProvider).isListed(roomId),
);

/// A space this room is filed under, and whether it can be taken out of it.
@immutable
class RoomParent {
  const RoomParent({
    required this.id,
    required this.name,
    required this.canRemove,
  });

  final String id;
  final String name;

  /// Whether this account can write to *that space*.
  ///
  /// Not a question about the room being looked at. Detaching it is an
  /// `m.space.child` event in the parent, so somebody who runs the room and
  /// merely belongs to the space cannot do it, and somebody who runs the space
  /// can do it to a room they have no power in at all.
  final bool canRemove;
}

/// A space this room says it belongs to, which this account is not in.
///
/// Read from the room's own `m.space.parent` events. `setSpaceChild` has
/// always written one beside the child event, and until now nothing read
/// them — so a room knew which space it was in only when that space had been
/// joined and synced, and a room whose space had not been was simply filed
/// under Home with no hint that it was part of anything.
///
/// It is the room's claim, not the space's agreement. The specification is
/// explicit that a parent link is only to be trusted when the space lists the
/// room back, or when whoever wrote it had the power to change that space —
/// neither of which can be checked without being in the space. So this is
/// shown as a place to go and look, never as a fact about where the room is.
@immutable
class ClaimedParent {
  const ClaimedParent({required this.id, required this.via});

  final String id;

  /// Servers to try when joining it; the event carries them for this reason.
  final List<String> via;
}

/// What a room or a space looks like to the manage dialog.
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
    required this.parents,
    required this.claimedParents,
    required this.joinRule,
    required this.canRestrictToSpace,
    required this.history,
    required this.ownLevel,
    required this.permissions,
    required this.canDescribe,
    required this.canSetAvatar,
    required this.canChangeAccess,
    required this.canChangeHistory,
    required this.canPublish,
    required this.canChangePermissions,
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

  /// The joined spaces this room is filed under.
  ///
  /// Shown before something destructive, because being in a space is the part
  /// people forget: leaving a room that a space lists still leaves it listed,
  /// for everybody who can see that space.
  final List<RoomParent> parents;

  /// Spaces the room names as a parent that this account has not joined.
  final List<ClaimedParent> claimedParents;

  List<String> get parentNames => [for (final parent in parents) parent.name];

  /// Who can join, as the room states it. Null when it does not say.
  final JoinRules? joinRule;

  /// Whether "anyone in its space" is an answer this room can be given.
  ///
  /// It needs a space to refer to, and a room version that has the rule at
  /// all: `restricted` arrived in version 8, and a homeserver rejects it in
  /// anything older.
  final bool canRestrictToSpace;

  /// Who can read what was said before they arrived. Null when unset, which
  /// homeservers treat as [HistoryVisibility.shared].
  final HistoryVisibility? history;

  /// This account's own power level here.
  final int ownLevel;

  /// What each kind of action currently needs, for the ones that apply.
  final Map<RoomPermission, int> permissions;

  final bool canDescribe;
  final bool canSetAvatar;
  final bool canChangeAccess;
  final bool canChangeHistory;
  final bool canPublish;
  final bool canChangePermissions;
  final bool canInvite;
  final bool canDismantle;

  /// Whether anything on the settings page can be changed by this account.
  bool get canChangeAnything =>
      canDescribe ||
      canSetAvatar ||
      canChangeAccess ||
      canChangeHistory ||
      canPublish;

  /// Whether this account may change what [permission] requires, to [level].
  ///
  /// Editing power levels at all is not enough. The authorisation rules
  /// refuse a change to any entry that is currently above the level of the
  /// person making it, and refuse to set one above it — otherwise a moderator
  /// allowed to edit the event could simply write themselves into it.
  bool canSetPermission(RoomPermission permission, int level) =>
      canChangePermissions &&
      (permissions[permission] ?? 0) <= ownLevel &&
      level <= ownLevel;
}

/// What the manage dialog shows for one room or space.
///
/// Recomputed on the sync tick, so renaming it from another client — or from
/// this one — updates the dialog while it is open.
final roomAdminInfoProvider = Provider.family<RoomAdminInfo?, String>((
  ref,
  roomId,
) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);
  final room = client.getRoomById(roomId);
  if (room == null) return null;

  final parents = [
    for (final parent in client.rooms)
      if (parent.isSpace &&
          parent.membership == Membership.join &&
          childRoomIdsOf(parent).contains(roomId))
        RoomParent(
          id: parent.id,
          name: displaySafeName(parent.getLocalizedDisplayname()),
          canRemove: capabilities.canRemoveFromSpace(parent),
        ),
  ];
  final parentIds = {for (final parent in parents) parent.id};
  final powerLevels = room.getState(EventTypes.RoomPowerLevels)?.content;

  return RoomAdminInfo(
    name: displaySafeName(room.getLocalizedDisplayname()),
    topic: room.topic,
    alias: room.canonicalAlias,
    avatarMxc: room.avatar?.toString(),
    // The server's count when it has sent one, because lazy loading means the
    // members held locally are only the ones who have spoken lately. Falling
    // back to those is "as far as this client knows", which is honest enough
    // for a line that exists to give a sense of scale.
    memberCount:
        room.summary.mJoinedMemberCount ??
        room.getParticipants(const [Membership.join]).length,
    childCount: room.isSpace ? childRoomIdsOf(room).length : 0,
    isSpace: room.isSpace,
    isDirect: room.isDirectChat,
    directUserId: room.directChatMatrixID,
    isEncrypted: room.encrypted,
    parents: parents,
    claimedParents: [
      for (final claimed in room.spaceParents)
        if (claimed.roomId case final id?
            when !parentIds.contains(id) &&
                client.getRoomById(id)?.membership != Membership.join)
          ClaimedParent(id: id, via: claimed.via),
    ],
    joinRule: room.joinRules,
    canRestrictToSpace:
        parents.isNotEmpty && (int.tryParse(room.roomVersion ?? '') ?? 0) >= 8,
    history: room.historyVisibility,
    ownLevel: room.ownPowerLevel.level,
    permissions: {
      for (final permission in RoomPermission.values)
        if (permission.appliesTo(isSpace: room.isSpace))
          permission: requiredLevel(powerLevels, permission),
    },
    canDescribe: capabilities.canDescribe(room),
    canSetAvatar: capabilities.canSetAvatar(room),
    canChangeAccess: capabilities.canChangeAccess(room),
    canChangeHistory: capabilities.canChangeHistory(room),
    canPublish: capabilities.canPublish(room),
    canChangePermissions: capabilities.canChangePermissions(room),
    canInvite: capabilities.canInvite(room),
    canDismantle: capabilities.canDismantle(room),
  );
});

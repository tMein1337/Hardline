// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/room_capabilities.dart' as capabilities;
import '../../core/matrix/room_permissions.dart';
import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/display_name.dart';

/// How somebody stands in a room, in the order the list groups them.
enum MemberStanding {
  joined('In the room'),
  invited('Invited'),
  knocking('Asked to join'),
  banned('Banned');

  const MemberStanding(this.heading);

  final String heading;

  static MemberStanding? of(Membership membership) => switch (membership) {
    Membership.join => joined,
    Membership.invite => invited,
    Membership.knock => knocking,
    Membership.ban => banned,
    // Somebody who left is not in the list at all. A room's history holds
    // everybody who ever passed through, and a member list is not that.
    Membership.leave => null,
  };
}

/// One person in a room's member list.
///
/// A value, with everything this account may do to them already decided. The
/// list is drawn from these and the buttons are drawn from the booleans, so
/// no widget asks the SDK a question and no button exists that the homeserver
/// would refuse.
@immutable
class RoomMember {
  const RoomMember({
    required this.userId,
    required this.name,
    required this.avatarMxc,
    required this.standing,
    required this.level,
    required this.isSelf,
    required this.canKick,
    required this.canBan,
    required this.canUnban,
    required this.grantable,
  });

  final String userId;
  final String name;
  final String? avatarMxc;
  final MemberStanding standing;

  /// Their power level here.
  final int level;

  final bool isSelf;

  final bool canKick;
  final bool canBan;
  final bool canUnban;

  /// The roles this account may give them, their current one aside.
  ///
  /// Empty when it may give none — which is what hides the control, rather
  /// than a separate "can change role" that could disagree with it.
  final List<RoomRole> grantable;

  String get role => roleLabel(level);

  /// Whether anything at all can be done to them from here.
  bool get hasActions => canKick || canBan || canUnban || grantable.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomMember &&
          userId == other.userId &&
          name == other.name &&
          avatarMxc == other.avatarMxc &&
          standing == other.standing &&
          level == other.level &&
          isSelf == other.isSelf &&
          canKick == other.canKick &&
          canBan == other.canBan &&
          canUnban == other.canUnban &&
          listEquals(grantable, other.grantable);

  @override
  int get hashCode => Object.hash(
    userId,
    name,
    avatarMxc,
    standing,
    level,
    isSelf,
    canKick,
    canBan,
    canUnban,
    Object.hashAll(grantable),
  );
}

/// Everybody in a room, grouped and ordered.
@immutable
class RoomMemberList {
  const RoomMemberList(this.members);

  /// Joined first, then invited, then knocking, then banned; within each,
  /// highest power level first and by name after that.
  final List<RoomMember> members;

  List<RoomMember> standing(MemberStanding standing) => [
    for (final member in members)
      if (member.standing == standing) member,
  ];

  /// Those whose name or id contains [query], ignoring case.
  ///
  /// Both, because the name is what somebody remembers and the id is the only
  /// part of an identity that is unique — two people can be called Alex.
  RoomMemberList matching(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return this;
    return RoomMemberList([
      for (final member in members)
        if (member.name.toLowerCase().contains(needle) ||
            member.userId.toLowerCase().contains(needle))
          member,
    ]);
  }
}

/// Fetches a room's complete member list from the homeserver, once.
///
/// **Why this exists at all.** The client syncs with lazy loading, so a room
/// holds only the members who have said something recently. That is enough to
/// put names on messages and nowhere near enough to manage a room: somebody
/// who joined a year ago and has never spoken is not in local state, and is
/// exactly who a member list is for.
///
/// The members are written into the room's own state, so [roomMembersProvider]
/// — which reads that state on every sync — has all of them and keeps them
/// current. A kick made from another client arrives as a state event like any
/// other and the row moves.
///
/// `cache: true` is deliberate and has a price. The SDK only caches members
/// by default in encrypted rooms, because holding fifty thousand of them for
/// a public room costs memory for nothing; here somebody has opened the list
/// and asked to see them. Past [_cacheCeiling] it is left off, and the list is
/// then whatever the server said when it was opened.
final roomMembersLoadProvider = FutureProvider.autoDispose
    .family<List<RoomMember>, String>((ref, roomId) async {
      final client = ref.watch(clientProvider);
      final room = client.getRoomById(roomId);
      if (room == null) return const [];

      final known = room.summary.mJoinedMemberCount ?? 0;
      final users = await room.requestParticipants(
        const [
          Membership.join,
          Membership.invite,
          Membership.knock,
          Membership.ban,
        ],
        // The warning is about doing this without meaning to.
        true,
        known <= _cacheCeiling,
        // Not "only if the local list looks incomplete". The SDK decides that
        // by comparing counts, and bans are in neither count.
        true,
      );
      return _describe(room, users);
    });

/// Above this many members the full list is not kept in memory.
const _cacheCeiling = 5000;

/// A room's members as currently known, recomputed on every sync.
///
/// Reads loaded state only and makes no request — [roomMembersLoadProvider]
/// is what fills that state in. Until it has, this is the lazy-loaded subset,
/// which is worth showing straight away rather than a spinner over an empty
/// box: the people at the top of a member list are mostly the ones who talk.
final roomMembersProvider = Provider.autoDispose.family<RoomMemberList, String>(
  (ref, roomId) {
    ref.watch(matrixTickProvider);
    final room = ref.watch(clientProvider).getRoomById(roomId);
    if (room == null) return const RoomMemberList([]);

    final loaded = room.getParticipants(const [
      Membership.join,
      Membership.invite,
      Membership.knock,
      Membership.ban,
    ]);

    // A room too large to cache has members the state never received. Those
    // come from the one-off fetch, with anything the state does hold laid over
    // the top, since the state is what sync keeps current.
    final fetched =
        ref.watch(roomMembersLoadProvider(roomId)).value ?? const [];
    final byId = {
      for (final member in fetched) member.userId: member,
      for (final member in _describe(room, loaded)) member.userId: member,
    };

    // The fetch is a snapshot; somebody it lists may have left since. Sync
    // records that as a member event too, and it is the newer of the two.
    byId.removeWhere(
      (userId, _) =>
          room
              .getState(EventTypes.RoomMember, userId)
              ?.asUser(room)
              .membership ==
          Membership.leave,
    );

    final members = byId.values.toList()
      ..sort((a, b) {
        final standing = a.standing.index.compareTo(b.standing.index);
        if (standing != 0) return standing;
        final level = b.level.compareTo(a.level);
        if (level != 0) return level;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return RoomMemberList(members);
  },
);

List<RoomMember> _describe(Room room, List<User> users) {
  final me = room.client.userID;
  return [
    for (final user in users)
      if (MemberStanding.of(user.membership) case final standing?)
        RoomMember(
          userId: user.id,
          name: displaySafeName(user.calcDisplayname()),
          avatarMxc: user.avatarUrl?.toString(),
          standing: standing,
          level: user.powerLevel.level,
          isSelf: user.id == me,
          canKick: capabilities.canKickMember(room, user.id),
          canBan: capabilities.canBanMember(room, user.id),
          canUnban: capabilities.canUnbanMember(room, user.id),
          // Roles mean something for people who are in the room. Somebody
          // invited or banned can be given a level, and nothing reads it.
          grantable: standing == MemberStanding.joined
              ? [
                  for (final role in RoomRole.values)
                    if (role.level != user.powerLevel.level &&
                        capabilities.canSetLevel(room, user.id, role.level))
                      role,
                ]
              : const [],
        ),
  ];
}

/// People this account already shares a room with, for the invite dialog.
///
/// What the invite field was missing. It takes a user id because there is no
/// directory to search that works everywhere — but nearly everybody somebody
/// wants to invite is already in a room with them, and their id is sitting in
/// local state. This offers those, and the field still takes anything.
///
/// Loaded members only, and no request: across every room that is the people
/// who have been active, which is the right short list.
@immutable
class KnownPerson {
  const KnownPerson({
    required this.userId,
    required this.name,
    required this.avatarMxc,
  });

  final String userId;
  final String name;
  final String? avatarMxc;
}

/// Known people matching [query] who could still be invited to [roomId].
///
/// Pure over the client, so the matching can be tested without a widget.
/// Nobody is offered who is already in the room, invited to it, or banned
/// from it — the first two would fail, and the third should be a decision
/// somebody makes on the member list rather than a name that autocompletes.
List<KnownPerson> invitableMatching(
  Client client, {
  required String roomId,
  required String query,
  int limit = 6,
}) {
  final needle = query.trim().toLowerCase().replaceFirst('@', '');
  if (needle.isEmpty) return const [];

  final target = client.getRoomById(roomId);
  final me = client.userID;
  final found = <String, KnownPerson>{};

  for (final room in client.rooms) {
    if (room.membership != Membership.join || room.id == roomId) continue;
    for (final user in room.getParticipants(const [Membership.join])) {
      if (user.id == me || found.containsKey(user.id)) continue;

      final standing = target
          ?.getState(EventTypes.RoomMember, user.id)
          ?.asUser(target)
          .membership;
      if (standing == Membership.join ||
          standing == Membership.invite ||
          standing == Membership.ban) {
        continue;
      }

      final name = displaySafeName(user.calcDisplayname());
      if (!name.toLowerCase().contains(needle) &&
          !user.id.toLowerCase().contains(needle)) {
        continue;
      }
      found[user.id] = KnownPerson(
        userId: user.id,
        name: name,
        avatarMxc: user.avatarUrl?.toString(),
      );
    }
  }

  final people = found.values.toList()
    ..sort((a, b) {
      // Somebody whose name *starts* with what was typed is the likelier
      // answer than somebody who has it in the middle.
      final aStarts = a.name.toLowerCase().startsWith(needle) ? 0 : 1;
      final bStarts = b.name.toLowerCase().startsWith(needle) ? 0 : 1;
      if (aStarts != bStarts) return aStarts.compareTo(bStarts);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return people.take(limit).toList();
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// What this account may do in a room.
///
/// One place to ask "may I", so an affordance is never shown on a guess and
/// never hidden on one either. Before this the only capability check in the
/// whole app was `voice_joinability.dart`, which asks a single voice-specific
/// question — everything else simply drew the control and let the server say
/// no after the click.
///
/// Every answer here is about *power levels*, which the client already has
/// from sync (`m.room.power_levels` is in `importantStateEvents`). None of
/// them is a network call, so they are safe to call from `build`.

/// Whether a room may be added to [space] as a child.
///
/// Writing an `m.space.child` event is what putting a room in a space means,
/// and it is a state event like any other.
bool canAddToSpace(Room space) =>
    space.isSpace &&
    space.membership == Membership.join &&
    space.canChangeStateEvent(EventTypes.SpaceChild);

/// Whether this account can invite somebody to [room].
///
/// A space is a room, so this answers for both.
bool canInvite(Room room) =>
    room.membership == Membership.join && room.canInvite;

/// Whether a room may be taken out of [space] again.
///
/// The same event as putting one in — removing a child is writing its
/// `m.space.child` with nothing in it — so the same answer. Named separately
/// because the two are asked from different places and "can add" is a strange
/// thing to read beside a remove button.
bool canRemoveFromSpace(Room space) => canAddToSpace(space);

/// Whether this account can rename [room] or change its topic.
///
/// Two separate state events, and a homeserver could permit one and not the
/// other — but no room in practice does, and a settings pane where the name
/// field is live and the topic field is not would raise more questions than it
/// answers. Asked together, refused together.
///
/// `canChangeStateEvent`, and it used to be `canSendEvent`. The difference is
/// the fallback: for an event type the power-levels event does not mention,
/// the first uses `state_default` and the second `events_default` — 50 and 0
/// in an ordinary room. Synapse's defaults name `m.room.name` and not
/// `m.room.topic`, so the name half of this was carrying the whole answer; on
/// a homeserver that names neither, every member was shown two live fields
/// and a Save button the server would refuse.
bool canDescribe(Room room) =>
    room.membership == Membership.join &&
    room.canChangeStateEvent(EventTypes.RoomName) &&
    room.canChangeStateEvent(EventTypes.RoomTopic);

/// Whether this account can change [room]'s picture.
bool canSetAvatar(Room room) =>
    room.membership == Membership.join &&
    room.canChangeStateEvent(EventTypes.RoomAvatar);

/// Whether this account can change who is able to join [room].
bool canChangeAccess(Room room) =>
    room.membership == Membership.join && room.canChangeJoinRules;

/// Whether this account can change who is able to read [room]'s history.
bool canChangeHistory(Room room) =>
    room.membership == Membership.join && room.canChangeHistoryVisibility;

/// Whether this account can list [room] in the homeserver's directory.
///
/// The one question here the power levels do not strictly answer. The
/// directory is the homeserver's own, not part of the room, and the
/// specification leaves who may edit it to the server. What servers do in
/// practice is ask for the level that changing the room's address needs, so
/// that is what is asked — and the request can still be refused, which the
/// dialog reports rather than assumes away.
bool canPublish(Room room) =>
    room.membership == Membership.join &&
    room.canChangeStateEvent(EventTypes.RoomCanonicalAlias);

/// Whether this account can change who may do what in [room], and what role
/// somebody has.
bool canChangePermissions(Room room) =>
    room.membership == Membership.join && room.canChangePowerLevel;

/// Whether this account can remove [userId] from [room].
///
/// Three things have to hold and the last is the one that surprises people:
/// the room has to let this account remove anybody at all, the person has to
/// be in a state they can be removed *from*, and they have to rank strictly
/// below — a moderator cannot remove another moderator, however the room is
/// configured.
bool canKickMember(Room room, String userId) {
  if (userId == room.client.userID) return false;
  final member = room.getState(EventTypes.RoomMember, userId)?.asUser(room);
  return member != null && member.canKick;
}

/// Whether this account can ban [userId] from [room].
///
/// Unlike [canKickMember] this does not need them to be here: banning
/// somebody who has left, or who has never been in, is how they are kept out.
bool canBanMember(Room room, String userId) {
  if (userId == room.client.userID) return false;
  final member = room.getState(EventTypes.RoomMember, userId)?.asUser(room);
  if (member != null && member.membership == Membership.ban) return false;
  return room.canBan && room.getPowerLevelByUserId(userId) < room.ownPowerLevel;
}

/// Whether this account can lift a ban on [userId].
///
/// Needs the level for banning **and** the one for removing people. Lifting a
/// ban is a change of membership to `leave`, which is what a kick is, and the
/// authorisation rules check it as both.
bool canUnbanMember(Room room, String userId) {
  final member = room.getState(EventTypes.RoomMember, userId)?.asUser(room);
  if (member == null || member.membership != Membership.ban) return false;
  return room.canBan &&
      room.canKick &&
      room.getPowerLevelByUserId(userId) < room.ownPowerLevel;
}

/// Whether this account can give [userId] the level [level] in [room].
///
/// Two limits beyond being allowed to edit power levels at all, both from the
/// authorisation rules rather than from taste:
///
///  * **Nobody can be raised above the person doing it.** An admin can make
///    admins; a moderator who has been allowed to edit levels can make
///    moderators and nothing higher.
///  * **Somebody already at or above cannot be touched**, with one exception
///    — yourself, downwards. Stepping down is always permitted and cannot be
///    undone by the person who did it, which is why the dialog asks first.
bool canSetLevel(Room room, String userId, int level) {
  if (!canChangePermissions(room)) return false;
  final own = room.ownPowerLevel.level;
  if (level > own) return false;
  final current = room.getPowerLevelByUserId(userId).level;
  if (userId == room.client.userID) return level <= current;
  return current < own;
}

/// Whether this account can take [room] apart.
///
/// The strongest question this file asks, and the one gating the destructive
/// path in `RoomManageDialog`. Deliberately the *conjunction* of what taking
/// something apart actually needs, rather than a single "am I an admin" proxy:
/// somebody who can remove a space's children but cannot kick would get
/// halfway through and stop, having emptied it and left everybody inside.
///
/// A space additionally needs to be able to release its children. A room does
/// not — detaching it from whatever space lists it needs power in *that*
/// space, which is a different room, so it is attempted and reported rather
/// than required. See `RoomAdmin.dismantle`.
///
/// **Never offered for a direct chat.** Dismantling one means kicking the
/// person you were talking to, which is a strange way to end a conversation;
/// leaving is the answer there, and it is always available.
bool canDismantle(Room room) {
  if (room.membership != Membership.join) return false;
  if (room.isDirectChat) return false;
  if (!room.canKick) return false;
  // `canChangeStateEvent`, for the reason given on [canDescribe]: a space
  // whose power levels do not mention `m.space.child` needs `state_default`
  // for it, not the nothing that `canSendEvent` falls back to.
  return !room.isSpace || room.canChangeStateEvent(EventTypes.SpaceChild);
}

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

/// Whether this account can rename [room] or change its topic.
///
/// Two separate state events, and a homeserver could permit one and not the
/// other — but no room in practice does, and a settings pane where the name
/// field is live and the topic field is not would raise more questions than it
/// answers. Asked together, refused together.
bool canDescribe(Room room) =>
    room.membership == Membership.join &&
    room.canSendEvent(EventTypes.RoomName) &&
    room.canSendEvent(EventTypes.RoomTopic);

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
  return !room.isSpace || room.canSendEvent(EventTypes.SpaceChild);
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// "Who may do what" in a room, as numbers and as words.
///
/// Matrix answers that question with one state event, `m.room.power_levels`:
/// every person has a level, every action needs one, and you may do the thing
/// if yours is at least what it asks. Everything here works on the *content*
/// of that event as a plain map, and nothing in this file touches the SDK —
/// so the rules can be read and tested without a room to ask them of.
library;

/// The three levels every Matrix client agrees to give names to.
///
/// The numbers are conventions, not protocol: a level is any integer, and a
/// room may use 25 or 75 for something of its own. These are the ones a
/// freshly made room starts with, and the only ones this app will *set* — a
/// level it merely finds is shown as what it is, see [roleLabel].
enum RoomRole {
  member(0, 'Member'),
  moderator(50, 'Moderator'),
  admin(100, 'Admin');

  const RoomRole(this.level, this.label);

  final int level;
  final String label;

  /// The role sitting exactly at [level], or null for anything in between.
  static RoomRole? at(int level) =>
      values.where((role) => role.level == level).firstOrNull;
}

/// From room version 12 the creator outranks every number.
///
/// The SDK represents that as the largest integer a JSON number can hold
/// (`PowerLevel.ownerPowerLevel`), which is the right thing to compare against
/// and the wrong thing to print.
const kCreatorLevel = 9007199254740991;

/// What to call somebody at [level].
///
/// A level between the named ones is not rounded to the nearest: "Moderator"
/// for somebody at 60 would hide the one fact that explains why a moderator at
/// 50 cannot remove them.
String roleLabel(int level) {
  if (level >= kCreatorLevel) return 'Creator';
  final role = RoomRole.at(level);
  if (role != null) return role.label;
  if (level > RoomRole.admin.level) return 'Admin ($level)';
  if (level < RoomRole.member.level) return 'Restricted ($level)';
  return 'Custom ($level)';
}

/// One thing a level can be required for.
///
/// Not the whole of `m.room.power_levels`, on purpose. The event can name a
/// level for any event type there is, and a screen offering all of them is a
/// screen nobody can use. These are the ones a person running a room actually
/// reaches for, in the words they would use for them.
enum RoomPermission {
  sendMessages(
    'Send messages',
    'Everything that is not a change to the room itself.',
    [_Key.field('events_default')],
  ),
  invite('Invite people', null, [_Key.field('invite')]),
  kick('Remove people', 'They can come back if the room lets them.', [
    _Key.field('kick'),
  ]),
  ban('Ban people', 'And lift a ban.', [_Key.field('ban')]),
  redact(
    'Remove other people\'s messages',
    'Everybody can always remove their own.',
    [_Key.field('redact')],
  ),
  describe('Change the name, topic and picture', null, [
    _Key.event('m.room.name'),
    _Key.event('m.room.topic'),
    _Key.event('m.room.avatar'),
  ]),
  manageRooms(
    'Add and remove rooms',
    'Which rooms this space lists. It does not change the rooms themselves.',
    [_Key.event('m.space.child')],
    spacesOnly: true,
  ),
  calls(
    'Join and start calls',
    'Being in a call is a change to the room, so it needs permission of its '
        'own or it inherits the one for settings.',
    [_Key.event('org.matrix.msc3401.call.member')],
    roomsOnly: true,
  ),
  settings(
    'Change other settings',
    'Who can join, who can read the history, and anything else not listed '
        'here.',
    [_Key.field('state_default')],
  ),
  permissions(
    'Change these permissions',
    'And change what role somebody has.',
    [_Key.event('m.room.power_levels')],
  );

  const RoomPermission(
    this.label,
    this.detail,
    this._keys, {
    this.spacesOnly = false,
    this.roomsOnly = false,
  });

  final String label;
  final String? detail;
  final List<_Key> _keys;

  /// Only meaningful in a space, which is the only thing with children.
  final bool spacesOnly;

  /// Only meaningful in a room: a space holds no conversation and no call.
  final bool roomsOnly;

  /// Whether this is worth showing for a room, or for a space.
  bool appliesTo({required bool isSpace}) => isSpace ? !roomsOnly : !spacesOnly;
}

/// Where in the power-levels event one requirement lives.
class _Key {
  /// A top-level field, like `kick`.
  const _Key.field(this.name) : isEvent = false;

  /// An entry in the `events` map, keyed by event type.
  const _Key.event(this.name) : isEvent = true;

  final String name;
  final bool isEvent;
}

/// The level [permission] currently asks for.
///
/// [content] is the content of `m.room.power_levels`, or null for a room that
/// has never had one.
///
/// A permission spread over several event types — the name, the topic and the
/// picture — reports the **highest** of them. Reporting the lowest would say
/// "members can do this" about a room where they can change the topic and not
/// the name, and the control would then fail on the click for two thirds of
/// what it claims to cover.
int requiredLevel(Map<String, Object?>? content, RoomPermission permission) {
  var highest = _levelFor(content, permission._keys.first);
  for (final key in permission._keys.skip(1)) {
    final level = _levelFor(content, key);
    if (level > highest) highest = level;
  }
  return highest;
}

int _levelFor(Map<String, Object?>? content, _Key key) {
  if (!key.isEvent) return _field(content, key.name);

  final events = content?['events'];
  final explicit = events is Map ? events[key.name] : null;
  // Every permission here that names an event type names a *state* event, so
  // the fallback is `state_default` and never `events_default`. Getting that
  // backwards is easy and says "anybody may rename this room" about every
  // room whose `events` map does not happen to mention the name.
  return explicit is int ? explicit : _field(content, 'state_default');
}

/// A top-level field, with the default the specification gives it.
///
/// The defaults differ depending on whether the event exists at all. With no
/// power-levels event the creator is at 100 and everybody else at 0, and
/// nothing needs more than 0 except removing people; with one that merely
/// omits a field, changing the room needs 50.
int _field(Map<String, Object?>? content, String name) {
  final value = content?[name];
  if (value is int) return value;
  return switch (name) {
    'kick' || 'ban' || 'redact' => 50,
    'state_default' => content == null ? 0 : 50,
    _ => 0,
  };
}

/// [content] with [permission] asking for [level], and nothing else changed.
///
/// A copy, never an edit in place: the map handed in belongs to a state event
/// the SDK is still holding, and writing through it would change what the
/// room believes before the homeserver has agreed to anything.
///
/// Everything not being changed is carried over as it was found — including
/// the fields this file has no name for. Rebuilding the event from the parts
/// understood here would silently reset every level some other client had set
/// for an event type this app has never heard of.
Map<String, Object?> withRequiredLevel(
  Map<String, Object?>? content,
  RoomPermission permission,
  int level,
) {
  final next = <String, Object?>{...?content};
  final events = <String, Object?>{
    if (next['events'] case final Map existing)
      for (final entry in existing.entries) entry.key.toString(): entry.value,
  };

  for (final key in permission._keys) {
    if (key.isEvent) {
      events[key.name] = level;
    } else {
      next[key.name] = level;
    }
  }

  if (events.isNotEmpty || next.containsKey('events')) next['events'] = events;
  return next;
}

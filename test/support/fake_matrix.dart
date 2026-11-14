// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// `Visibility` is both a Flutter widget and a Matrix enum; see the same note
// in `create_room_dialog.dart`.
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:matrix/matrix.dart' as mx show Visibility;

/// A homeserver small enough to hold in a test.
///
/// A real [Client] with the network taken out. The rooms in it are real
/// [Room] objects carrying real state events, so everything the app asks of
/// the SDK — power levels, membership, what a space contains — is answered by
/// the SDK's own code rather than by a guess at what it would say.
///
/// Only the requests are faked, and each one does two things: it is written to
/// [calls], so a test can assert what was *sent*, and it applies to the rooms
/// what a homeserver would have sent back down sync, so the screen under test
/// moves on the way the real one would.
///
/// Anything not overridden here still goes to the network, and with no
/// homeserver set that throws — which is the right answer for a test that
/// reaches for a request nobody expected.
class FakeMatrixClient extends Client {
  FakeMatrixClient({this.me = '@me:example.org'})
    : super('fake', database: _NoDatabase());

  /// Who this client is signed in as.
  final String me;

  @override
  String? get userID => me;

  /// Every request made, in order, as one readable line each.
  final List<String> calls = [];

  /// Requests the server will refuse, by the first word of their [calls] line.
  ///
  /// `refuse['kick'] = MatrixException...` makes every kick fail; removing the
  /// entry lets them through again.
  final Map<String, Object> refuse = {};

  /// Members the server knows about and this client has not loaded.
  ///
  /// What lazy loading leaves out, and what `/members` returns on top of the
  /// state already in the room.
  final Map<String, List<MatrixEvent>> unloadedMembers = {};

  /// What `/hierarchy` returns for a space, one entry per page.
  final Map<String, List<List<SpaceRoomsChunk$2>>> hierarchyPages = {};

  /// Rooms published in the directory.
  final Set<String> listed = {};

  int _events = 0;
  int _syncs = 0;

  // ---------------------------------------------------------------------------
  // Building a world
  // ---------------------------------------------------------------------------

  /// Adds a room this account is in, and returns it.
  ///
  /// [levels] gives people a power level; anybody not named has the default of
  /// zero. [events] is the `events` map of the power-levels event, for a room
  /// where a particular state event needs more or less than the default.
  /// [version] matters from 12 on, where the creator outranks everything.
  Room addRoom(
    String id, {
    String? name,
    bool space = false,
    String creator = '@creator:example.org',
    Map<String, int> levels = const {},
    Map<String, int> events = const {},
    Map<String, Object?> powerLevels = const {},
    bool withPowerLevels = true,
    String version = '10',
    Membership membership = Membership.join,
    List<String> members = const [],
  }) {
    final room = Room(id: id, client: this, membership: membership);
    rooms.add(room);

    state(id, EventTypes.RoomCreate, {
      'room_version': version,
      if (space) 'type': 'm.space',
    }, sender: creator);
    if (name != null) state(id, EventTypes.RoomName, {'name': name});
    if (withPowerLevels) {
      state(id, EventTypes.RoomPowerLevels, {
        'users': levels,
        'users_default': 0,
        'events': events,
        'events_default': 0,
        'state_default': 50,
        'invite': 0,
        'kick': 50,
        'ban': 50,
        'redact': 50,
        ...powerLevels,
      });
    }
    member(id, me);
    for (final userId in members) {
      member(id, userId);
    }
    return room;
  }

  /// Sets one state event, as though it had come down sync.
  void state(
    String roomId,
    String type,
    Map<String, Object?> content, {
    String stateKey = '',
    String? sender,
  }) {
    getRoomById(roomId)!.setState(
      StrippedStateEvent(
        type: type,
        content: content,
        senderId: sender ?? me,
        stateKey: stateKey,
      ),
    );
  }

  /// Puts somebody in a room, or changes how they stand in it.
  void member(
    String roomId,
    String userId, {
    Membership membership = Membership.join,
    String? displayName,
  }) => state(
    roomId,
    EventTypes.RoomMember,
    {'membership': membership.name, 'displayname': ?displayName},
    stateKey: userId,
    sender: userId,
  );

  /// Files [childId] under [spaceId], the way `m.space.child` does.
  void child(String spaceId, String childId, {String order = ''}) =>
      state(spaceId, EventTypes.SpaceChild, {
        'via': ['example.org'],
        if (order.isNotEmpty) 'order': order,
      }, stateKey: childId);

  /// One room as `/hierarchy` describes it.
  static SpaceRoomsChunk$2 summary(
    String roomId, {
    String? name,
    bool space = false,
    int members = 1,
  }) => SpaceRoomsChunk$2(
    roomId: roomId,
    name: name,
    numJoinedMembers: members,
    guestCanJoin: false,
    worldReadable: false,
    roomType: space ? 'm.space' : null,
    childrenState: [],
  );

  /// Tells whoever is listening that the store changed.
  ///
  /// The app recomputes from `matrixTickProvider`, which listens to exactly
  /// this stream. Without it a fake request would change the rooms and the
  /// screen would never find out.
  void synced() => onSync.add(SyncUpdate(nextBatch: 's${++_syncs}'));

  // ---------------------------------------------------------------------------
  // The requests
  // ---------------------------------------------------------------------------

  void _request(String line) {
    calls.add(line);
    final verb = line.split(' ').first;
    final refusal = refuse[verb];
    if (refusal != null) throw refusal;
  }

  /// What a homeserver says to a request this account lacks the power for.
  static MatrixException forbidden([String message = 'You are not allowed']) =>
      MatrixException.fromJson({'errcode': 'M_FORBIDDEN', 'error': message});

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    _request('state $roomId $eventType${stateKey.isEmpty ? '' : ' $stateKey'}');
    state(roomId, eventType, body, stateKey: stateKey);
    synced();
    return '\$event${++_events}';
  }

  void _membership(String roomId, String userId, Membership membership) {
    final room = getRoomById(roomId);
    if (room == null) return;
    final existing = room.getState(EventTypes.RoomMember, userId);
    state(
      roomId,
      EventTypes.RoomMember,
      {...?existing?.content, 'membership': membership.name},
      stateKey: userId,
      sender: me,
    );
    synced();
  }

  @override
  Future<void> kick(String roomId, String userId, {String? reason}) async {
    _request('kick $roomId $userId');
    _membership(roomId, userId, Membership.leave);
  }

  @override
  Future<void> ban(String roomId, String userId, {String? reason}) async {
    _request('ban $roomId $userId');
    _membership(roomId, userId, Membership.ban);
  }

  @override
  Future<void> unban(String roomId, String userId, {String? reason}) async {
    _request('unban $roomId $userId');
    _membership(roomId, userId, Membership.leave);
  }

  @override
  Future<void> inviteUser(
    String roomId,
    String userId, {
    String? reason,
  }) async {
    _request('invite $roomId $userId');
    _membership(roomId, userId, Membership.invite);
  }

  @override
  Future<List<MatrixEvent>?> getMembersByRoom(
    String roomId, {
    String? at,
    Membership? membership,
    Membership? notMembership,
  }) async {
    _request('members $roomId');
    final room = getRoomById(roomId)!;
    return [
      for (final loaded
          in room.states[EventTypes.RoomMember]?.values ??
              const <StrippedStateEvent>[])
        MatrixEvent(
          type: loaded.type,
          content: loaded.content,
          senderId: loaded.senderId,
          stateKey: loaded.stateKey,
          eventId: '\$member${++_events}',
          originServerTs: DateTime(2026),
        ),
      ...?unloadedMembers[roomId],
    ];
  }

  /// A member event for [unloadedMembers].
  static MatrixEvent memberEvent(
    String userId, {
    Membership membership = Membership.join,
    String? displayName,
  }) => MatrixEvent(
    type: EventTypes.RoomMember,
    content: {'membership': membership.name, 'displayname': ?displayName},
    senderId: userId,
    stateKey: userId,
    eventId: '\$unloaded-$userId',
    originServerTs: DateTime(2026),
  );

  @override
  Future<GetSpaceHierarchyResponse> getSpaceHierarchy(
    String roomId, {
    bool? suggestedOnly,
    int? limit,
    int? maxDepth,
    String? from,
  }) async {
    _request(
      'hierarchy $roomId depth=$maxDepth${from == null ? '' : ' from=$from'}',
    );
    final pages = hierarchyPages[roomId] ?? const [];
    final index = from == null ? 0 : int.parse(from);
    return GetSpaceHierarchyResponse(
      rooms: index < pages.length ? pages[index] : [],
      nextBatch: index + 1 < pages.length ? '${index + 1}' : null,
    );
  }

  @override
  Future<Uri> uploadContent(
    Uint8List file, {
    String? filename,
    String? contentType,
  }) async {
    _request('upload ${filename ?? ''} ${file.length}b');
    return Uri.parse('mxc://example.org/upload${++_events}');
  }

  @override
  Future<mx.Visibility?> getRoomVisibilityOnDirectory(String roomId) async {
    _request('directory? $roomId');
    return listed.contains(roomId)
        ? mx.Visibility.public
        : mx.Visibility.private;
  }

  @override
  Future<void> setRoomVisibilityOnDirectory(
    String roomId, {
    mx.Visibility? visibility,
  }) async {
    _request('directory $roomId ${visibility?.name}');
    if (visibility == mx.Visibility.public) {
      listed.add(roomId);
    } else {
      listed.remove(roomId);
    }
  }

  @override
  Future<String> joinRoom(
    Object? roomIdOrAlias, {
    List<String>? via,
    String? reason,
    ThirdPartySigned? thirdPartySigned,
  }) async {
    _request('join $roomIdOrAlias via=${via?.join(',') ?? ''}');
    return roomIdOrAlias.toString();
  }
}

/// The parts of a store the SDK touches on the paths these tests take.
///
/// Member loading reads the store before it asks the server and writes what
/// the server said back afterwards. Neither needs to remember anything here:
/// the rooms hold their own state for the length of a test.
class _NoDatabase extends Fake implements DatabaseApi {
  @override
  Future<List<User>> getUsers(Room room) async => const [];

  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {}

  @override
  Future<void> transaction(Future<void> Function() action) => action();
}

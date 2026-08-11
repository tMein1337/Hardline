import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/util/snapshot_list.dart';
import 'activity_prefs_controller.dart';
import 'activity_prefs_state.dart';
import 'activity_reducers.dart';

const _localizations = MatrixDefaultLocalizations();

/// Most records kept, regardless of age.
///
/// A ceiling rather than a target: a busy account can fill the horizon many
/// times over, and an unbounded log would grow for as long as the app runs.
const int _maxRecords = 400;

/// Coalescing window for emissions, and the longest an update is held back.
///
/// Same numbers and the same reason as `matrixTickProvider`: an initial sync
/// never goes quiet, so a pure trailing debounce would starve.
const Duration _debounceWindow = Duration(milliseconds: 120);
const Duration _maxWait = Duration(milliseconds: 500);

/// Events requested per room by the backfill.
///
/// Generous because the request carries a `senders` filter, so the whole limit
/// is spent on people being followed rather than on the room's general traffic.
const int _backfillPerRoom = 20;

enum BackfillPhase { idle, running, done, failed }

/// How the optional launch backfill is getting on.
@immutable
class BackfillProgress {
  const BackfillProgress({
    this.phase = BackfillPhase.idle,
    this.done = 0,
    this.total = 0,
    this.fetched = 0,
    this.error,
  });

  const BackfillProgress.idle() : this();

  final BackfillPhase phase;

  /// Rooms finished, and rooms to do. Both zero unless a run has started.
  final int done;
  final int total;

  /// Records actually added by the last completed run.
  final int fetched;

  final String? error;

  bool get isRunning => phase == BackfillPhase.running;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BackfillProgress &&
          phase == other.phase &&
          done == other.done &&
          total == other.total &&
          fetched == other.fetched &&
          error == other.error;

  @override
  int get hashCode => Object.hash(phase, done, total, fetched, error);
}

/// What the log exposes: the records, and how the backfill is doing.
///
/// One notifier rather than two because the backfill's only product *is*
/// records. Consumers `select` the half they care about, so progress ticking
/// from 3/30 to 4/30 does not recompute the lists.
@immutable
class ActivityLogState {
  const ActivityLogState({required this.entries, required this.backfill});

  const ActivityLogState.empty()
    : entries = const ListSnapshot.empty(),
      backfill = const BackfillProgress.idle();

  final ListSnapshot<MessageRecord> entries;
  final BackfillProgress backfill;

  ActivityLogState copyWith({
    ListSnapshot<MessageRecord>? entries,
    BackfillProgress? backfill,
  }) => ActivityLogState(
    entries: entries ?? this.entries,
    backfill: backfill ?? this.backfill,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActivityLogState &&
          entries == other.entries &&
          backfill == other.backfill;

  @override
  int get hashCode => Object.hash(entries, backfill);
}

/// A rolling record of who said something where, across every joined room.
///
/// Nothing in the SDK answers this. `Room.lastEvent` gives one event per room,
/// and anything richer means opening a `Timeline` per room — five live stream
/// subscriptions each, for rooms nobody is looking at. So this accumulates the
/// answer from the sync stream instead, seeded from `lastEvent` so a cold start
/// is not completely blank, and optionally backfilled from the server.
///
/// Not auto-dispose: it has to keep collecting while the activity page is
/// closed, or opening the page would show an empty list every time. See
/// `ActivityLogKeepAlive` in `home_shell.dart` for what starts it.
class MessageActivityLog extends Notifier<ActivityLogState> {
  final List<MessageRecord> _records = [];
  StreamSubscription<Event>? _subscription;
  Timer? _debounce;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _backfilling = false;
  bool _disposed = false;

  @override
  ActivityLogState build() {
    final client = ref.watch(clientProvider);

    // ref.read, deliberately: a watch would tear this whole notifier down —
    // subscription, records and all — every time a toggle was flipped in
    // settings. The prefs are a start-up snapshot here. Live changes reach the
    // feature through the derived providers, which do watch them.
    final prefs = ref.read(activityPrefsProvider);

    _seedFromLastEvents(client);
    _subscription = client.onTimelineEvent.stream.listen(_onEvent);

    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      unawaited(_subscription?.cancel());
      _subscription = null;
    });

    // Microtask, not a bare call: `backfillNow` publishes before its first
    // await, and `state` does not exist until this method has returned.
    if (prefs.backfillOnLaunch) {
      unawaited(Future.microtask(backfillNow));
    }

    return ActivityLogState(
      entries: ListSnapshot(_prune()),
      backfill: const BackfillProgress.idle(),
    );
  }

  /// Asks the server for each room's recent history.
  ///
  /// Safe to call at any time; overlapping calls are a no-op rather than a
  /// second run. Returns when every room has been tried.
  Future<void> backfillNow() async {
    if (_backfilling) return;

    final client = ref.read(clientProvider);
    final following = ref.read(activityPrefsProvider).following;

    // A `senders: []` filter has no useful answer, and the whole pass would be
    // one request per room for nothing.
    if (following.isEmpty) return;

    final rooms = _candidateRooms(client);
    if (rooms.isEmpty) return;

    _backfilling = true;
    var added = 0;
    _publish(
      backfill: BackfillProgress(
        phase: BackfillPhase.running,
        total: rooms.length,
      ),
    );

    try {
      final filter = jsonEncode(
        StateFilter(
          // Both types: in an encrypted room the wire type is
          // `m.room.encrypted`, so filtering on `m.room.message` alone comes
          // back empty from exactly the rooms most worth fetching.
          types: [EventTypes.Message, EventTypes.Encrypted],
          senders: following.toList(),
        ).toJson(),
      );

      for (var index = 0; index < rooms.length; index++) {
        // The provider can be torn down mid-run by an account switch, at which
        // point the remaining requests belong to a client nobody is using.
        if (_disposed) return;

        added += await _backfillRoom(client, rooms[index], filter);

        _publish(
          backfill: BackfillProgress(
            phase: BackfillPhase.running,
            done: index + 1,
            total: rooms.length,
            fetched: added,
          ),
        );
      }

      _publish(
        backfill: BackfillProgress(
          phase: BackfillPhase.done,
          done: rooms.length,
          total: rooms.length,
          fetched: added,
        ),
        force: true,
      );
    } catch (error, stack) {
      debugPrint('[activity] backfill failed: $error\n$stack');
      _publish(
        backfill: BackfillProgress(
          phase: BackfillPhase.failed,
          total: rooms.length,
          fetched: added,
          error: error.toString(),
        ),
        force: true,
      );
    } finally {
      _backfilling = false;
    }
  }

  /// Fetches one room's slice, returning how many records it contributed.
  ///
  /// Failures are logged and swallowed: one unreachable room makes the summary
  /// incomplete, which is untidy, where letting it throw would abandon every
  /// room after it.
  Future<int> _backfillRoom(Client client, Room room, String filter) async {
    try {
      final response = await client.getRoomEvents(
        room.id,
        Direction.b,
        limit: _backfillPerRoom,
        filter: filter,
      );

      var added = 0;
      for (final matrixEvent in response.chunk) {
        var event = Event.fromMatrixEvent(
          matrixEvent,
          room,
          status: EventStatus.synced,
        );

        final encryption = client.encryption;
        if (event.type == EventTypes.Encrypted && encryption != null) {
          // The same sequence `Room._refreshLastEvent` uses. History we hold no
          // megolm session for comes back still typed `m.room.encrypted`, and
          // `_record` drops it — an undecryptable placeholder in a summary is
          // worse than an absence, because it cannot be acted on.
          event = await encryption.decryptRoomEvent(event);
        }

        if (_record(event, room)) added++;
      }
      return added;
    } catch (error) {
      debugPrint('[activity] backfill of ${room.id} failed: $error');
      return 0;
    }
  }

  /// Every joined room worth asking about.
  List<Room> _candidateRooms(Client client) => [
    for (final room in client.rooms)
      if (!room.isSpace && room.membership == Membership.join) room,
  ];

  /// One event per room, so a cold start is not completely blank.
  ///
  /// `lastEvent` is what the SDK already persists for the room list preview, so
  /// this costs nothing — no network, no timeline, no decryption.
  void _seedFromLastEvents(Client client) {
    for (final room in _candidateRooms(client)) {
      final event = room.lastEvent;
      if (event != null) _record(event, room);
    }
  }

  void _onEvent(Event event) {
    if (_disposed) return;
    final room = event.room;
    if (room.isSpace || room.membership != Membership.join) return;
    if (!_record(event, room)) return;
    _schedule();
  }

  /// Adds [event] to the log if it is the kind of thing the summary shows.
  ///
  /// Returns whether anything was added, so the backfill can count and the live
  /// path can skip an emission for an event nobody will see.
  bool _record(Event event, Room room) {
    if (event.type != EventTypes.Message) return false;
    if (event.redacted) return false;
    // An edit is a second `m.room.message` pointing at the first. Recording it
    // would list the same message twice, the second time with the edit's body
    // under the original's timestamp.
    if (event.relationshipType == RelationshipTypes.edit) return false;
    // Our own messages are never shown: following yourself is refused, so these
    // could only ever be dead weight in the log.
    if (event.senderId == room.client.userID) return false;

    final timestamp = event.originServerTs;
    if (timestamp.isBefore(DateTime.now().subtract(kMaxRecentWindow))) {
      return false;
    }

    final body = event.calcLocalizedBodyFallback(
      _localizations,
      withSenderNamePrefix: false,
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
    );
    final preview = previewOf(body);
    if (preview.isEmpty) return false;

    _records.add(
      MessageRecord(
        eventId: event.eventId,
        roomId: room.id,
        userId: event.senderId,
        preview: preview,
        timestamp: timestamp,
      ),
    );
    return true;
  }

  List<MessageRecord> _prune() {
    final pruned = pruneActivities(
      _records,
      now: DateTime.now(),
      horizon: kMaxRecentWindow,
      cap: _maxRecords,
    );
    // Keep the working list bounded too, not just the published snapshot —
    // otherwise `_records` grows forever and every prune walks all of it.
    _records
      ..clear()
      ..addAll(pruned);
    return pruned;
  }

  void _schedule() {
    if (DateTime.now().difference(_lastEmit) > _maxWait) {
      _publish();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, _publish);
  }

  /// Recomputes the snapshot and publishes it.
  ///
  /// [force] skips the debounce bookkeeping for terminal backfill states, which
  /// must land even if nothing was added.
  void _publish({BackfillProgress? backfill, bool force = false}) {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = null;
    if (!force) _lastEmit = DateTime.now();

    state = ActivityLogState(
      entries: ListSnapshot(_prune()),
      backfill: backfill ?? state.backfill,
    );
  }
}

final messageActivityLogProvider =
    NotifierProvider<MessageActivityLog, ActivityLogState>(
      MessageActivityLog.new,
    );

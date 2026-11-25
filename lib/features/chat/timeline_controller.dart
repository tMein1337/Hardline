// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'mentions.dart';
import 'message_grouping.dart';
import 'message_item.dart';

enum TimelineStatus { loading, ready, error }

/// How many events to fetch per page.
const _pageSize = 50;

/// If the first page is this short it probably does not fill the viewport, so
/// another page is pulled immediately — otherwise there is nothing to scroll
/// and pagination can never trigger.
const _minEventsForViewport = 20;

/// Owns a room's [Timeline] and exposes it as display rows.
///
/// This is deliberately a `ChangeNotifier` rather than provider state. The
/// timeline is inherently mutable, high-frequency and imperatively paginated;
/// forcing it into value-equality snapshots would mean rebuilding a list of
/// hundreds of events on every keystroke-speed update. Riverpod still owns the
/// lifetime — see `timeline_provider.dart`.
class TimelineController extends ChangeNotifier {
  TimelineController({required this.client, required this.roomId}) {
    assert(() {
      liveInstanceCount++;
      return true;
    }());
  }

  final Client client;
  final String roomId;

  /// Debug-only leak counter. Switching rooms must return this to zero; a
  /// climbing value means `cancelSubscriptions` is being missed somewhere.
  @visibleForTesting
  static int liveInstanceCount = 0;

  Timeline? _timeline;
  bool _disposed = false;
  bool _loadingMore = false;
  Object? _error;
  TimelineStatus _status = TimelineStatus.loading;
  List<TimelineItem> _items = const [];

  TimelineStatus get status => _status;
  Object? get error => _error;
  List<TimelineItem> get items => _items;
  bool get isLoadingMore => _loadingMore;
  bool get canLoadMore => _timeline?.canRequestHistory ?? false;

  Future<void> start() async {
    try {
      final room = client.getRoomById(roomId);
      if (room == null) {
        throw StateError('Room $roomId is not in the local store');
      }

      final timeline = await room.getTimeline(
        limit: _pageSize,
        onUpdate: _onTimelineChanged,
        onInsert: (_) => _onTimelineChanged(),
        onChange: (_) => _onTimelineChanged(),
        onRemove: (_) => _onTimelineChanged(),
        onNewEvent: _onTimelineChanged,
      );

      // The user can select another room while getTimeline() is awaiting, by
      // which point this controller is already disposed. The Timeline
      // constructor has *already* attached its subscriptions, so they have to
      // be torn down here — ref.onDispose ran before this object existed and
      // cannot do it.
      if (_disposed) {
        timeline.cancelSubscriptions();
        return;
      }

      _timeline = timeline;
      _status = TimelineStatus.ready;
      _rebuildItems();
      notifyListeners();

      if (timeline.events.length < _minEventsForViewport &&
          timeline.canRequestHistory) {
        await loadMore();
      }
    } catch (error, stack) {
      if (_disposed) return;
      debugPrint('Could not open timeline for $roomId: $error\n$stack');
      _error = error;
      _status = TimelineStatus.error;
      notifyListeners();
    }
  }

  void _onTimelineChanged() {
    // Callbacks can still fire between cancelSubscriptions() and the stream
    // actually detaching, and notifyListeners() asserts after dispose.
    if (_disposed) return;
    _rebuildItems();
    notifyListeners();
  }

  void _rebuildItems() {
    final timeline = _timeline;
    _items = timeline == null ? const [] : buildTimelineItems(timeline);
  }

  /// The newest event a read receipt may point at, or null if there is none.
  ///
  /// Skips local echoes. Until the server has accepted a message its "event id"
  /// is the transaction id we invented, and a receipt for one of those is
  /// rejected — so the newest row on screen is regularly not the newest thing
  /// that can be marked read.
  String? get newestSyncedEventId {
    for (final item in _items) {
      final event = switch (item) {
        MessageItem(:final event) => event,
        SystemItem(:final event) => event,
        DateSeparatorItem() => null,
      };
      if (event == null || !event.status.isSent) continue;
      return event.eventId;
    }
    return null;
  }

  /// Where [eventId] sits in [items], or -1 if it is not loaded.
  ///
  /// Index into the *display* rows, not the timeline's events: the two differ
  /// by the date separators, and a caller scrolling to a row needs the former.
  int indexOfEvent(String eventId) =>
      _items.indexWhere((item) => item.key == eventId);

  /// The message [eventId] names, as it should be drawn — newest edit applied.
  ///
  /// For the quote above a reply. Answers at once when the event is loaded;
  /// otherwise null, and [fetchEvent] goes to the store or the server.
  Event? loadedDisplayEvent(String eventId) {
    final timeline = _timeline;
    if (timeline == null) return null;
    for (final event in timeline.events) {
      if (event.eventId == eventId) return event.getDisplayEvent(timeline);
    }
    return null;
  }

  /// Futures rather than events, so that a quote rebuilt while its request is
  /// still in flight waits on the same request instead of starting another.
  final _fetched = <String, Future<Event?>>{};

  /// Fetches a message that is not in the loaded timeline.
  ///
  /// Through `Timeline.getEventById`, which asks the local store first and
  /// decrypts what the server returns. A failure resolves to null — a reply
  /// whose quote cannot be found is still a readable message.
  Future<Event?> fetchEvent(String eventId) {
    final timeline = _timeline;
    if (timeline == null) return Future.value();
    return _fetched.putIfAbsent(eventId, () async {
      try {
        final event = await timeline.getEventById(eventId);
        if (event == null || _disposed) return event;
        return event.getDisplayEvent(timeline);
      } catch (error) {
        debugPrint('Could not fetch $eventId in $roomId: $error');
        return null;
      }
    });
  }

  /// Loads an older page. Safe to call repeatedly; overlapping calls are
  /// ignored.
  Future<void> loadMore() async {
    final timeline = _timeline;
    if (timeline == null ||
        _loadingMore ||
        timeline.isRequestingHistory ||
        !timeline.canRequestHistory) {
      return;
    }

    _loadingMore = true;
    notifyListeners();
    try {
      await timeline.requestHistory(historyCount: _pageSize);
    } catch (error) {
      debugPrint('Could not load more history for $roomId: $error');
    } finally {
      if (!_disposed) {
        _loadingMore = false;
        _rebuildItems();
        notifyListeners();
      }
    }
  }

  /// Sends a text message.
  ///
  /// The local echo appears synchronously via the timeline's onInsert callback,
  /// so the message shows before the network round trip completes.
  /// [candidates] are the room's members, for turning `@name` into a real
  /// mention. Empty is fine and means the message goes out as plain text.
  ///
  /// [inReplyTo] makes it a reply. It must be the *original* event, since the
  /// relation names its id.
  Future<void> send(
    String text, {
    List<MentionCandidate> candidates = const [],
    Event? inReplyTo,
  }) async {
    final body = text.trim();
    if (body.isEmpty) return;

    final room = client.getRoomById(roomId);
    if (room == null) return;

    try {
      // `m.mentions` is what actually pings somebody: the homeserver's push
      // rules read it, and a message that merely *says* "@Alice" reaches
      // nobody. Before this, every mention this client sent was decoration.
      //
      // The HTML half goes with it so Element draws a pill rather than the
      // literal text. Both are omitted entirely when nobody is named, so an
      // ordinary message is byte-for-byte what it always was.
      final mentioned = mentionedUserIds(body, candidates);
      if (mentioned.isEmpty) {
        // The SDK adds the replied-to sender to `m.mentions` itself here.
        await room.sendTextEvent(body, inReplyTo: inReplyTo);
        return;
      }

      // The spec asks a reply to mention whoever it answers, so their client
      // notifies them. Never ourselves: answering your own message is not a
      // reason to ping your other devices.
      final replyee = inReplyTo?.senderId;
      if (replyee != null && replyee != client.userID) mentioned.add(replyee);

      await room.sendEvent({
        'msgtype': MessageTypes.Text,
        'body': body,
        'format': 'org.matrix.custom.html',
        'formatted_body': formatMentions(body, candidates),
        'm.mentions': mentionsBlock(mentioned),
      }, inReplyTo: inReplyTo);
    } catch (error) {
      debugPrint('Could not send message to $roomId: $error');
    }
  }

  /// Sends staged attachments, optionally with [caption] as the message text.
  ///
  /// Uses [Room.sendFileEvent] and never [Client.uploadContent]. The latter
  /// uploads *plaintext* — in an encrypted room that silently ships the file to
  /// the server unprotected, and nothing downstream can tell. The SDK's own doc
  /// on uploadContent says to use this method for end-to-end encryption.
  ///
  /// It also hands us, for free: the local echo (a fake sync event at
  /// EventStatus.sending), `fileSendingStatus`, thumbnail generation with
  /// separate thumbnail encryption, the `m.upload.size` pre-check, a retrying
  /// upload loop, the cache write that later makes `Event.sendAgain()` work,
  /// and the transition to EventStatus.error on failure. All of it arrives
  /// through the existing onChange -> notifyListeners path with no new state.
  ///
  /// [inReplyTo] goes on the first event sent — the caption message when there
  /// is one of its own, otherwise the first file — so the batch answers the
  /// message once rather than once per file.
  Future<void> sendFiles(
    List<MatrixFile> files, {
    String caption = '',
    Event? inReplyTo,
  }) async {
    if (files.isEmpty) return;

    final room = client.getRoomById(roomId);
    if (room == null) return;

    final text = caption.trim();

    // MSC2530 attaches a caption to *one* file. With several, putting it on the
    // first makes Element render it under whichever image happens to lead,
    // which reads as a label for that image rather than for the batch. So: one
    // file gets a real caption; several get the text as its own message ahead
    // of them.
    var replyTo = inReplyTo;
    if (text.isNotEmpty && files.length > 1) {
      try {
        await room.sendTextEvent(text, inReplyTo: replyTo);
        replyTo = null;
      } catch (error) {
        debugPrint('Could not send the caption to $roomId: $error');
      }
    }

    for (final file in files) {
      final answering = replyTo;
      replyTo = null;
      try {
        await room.sendFileEvent(
          file,
          inReplyTo: answering,
          // sendFileEvent spreads extraContent last into the event content, so
          // this overrides 'body' while 'filename' keeps the real file name —
          // exactly the MSC2530 caption shape. Building the content by hand
          // would mean reimplementing the encrypted-file block as well.
          extraContent: text.isNotEmpty && files.length == 1
              ? {'body': text}
              : null,
        );
      } catch (error) {
        // The SDK has already flipped the local echo to EventStatus.error,
        // which the tile renders with a retry button. Same swallow-and-log as
        // send() above.
        debugPrint('Could not send an attachment to $roomId: $error');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // The Timeline holds five live stream subscriptions. Leaking one set per
    // room switch means decryption keeps running for rooms that are closed.
    _timeline?.cancelSubscriptions();
    _timeline = null;
    assert(() {
      liveInstanceCount--;
      return true;
    }());
    super.dispose();
  }
}

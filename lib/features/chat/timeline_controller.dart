import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

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
  Future<void> send(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;

    final room = client.getRoomById(roomId);
    if (room == null) return;

    try {
      await room.sendTextEvent(body);
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
  Future<void> sendFiles(List<MatrixFile> files, {String caption = ''}) async {
    if (files.isEmpty) return;

    final room = client.getRoomById(roomId);
    if (room == null) return;

    final text = caption.trim();

    // MSC2530 attaches a caption to *one* file. With several, putting it on the
    // first makes Element render it under whichever image happens to lead,
    // which reads as a label for that image rather than for the batch. So: one
    // file gets a real caption; several get the text as its own message ahead
    // of them, which is what Discord shows too.
    if (text.isNotEmpty && files.length > 1) {
      try {
        await room.sendTextEvent(text);
      } catch (error) {
        debugPrint('Could not send the caption to $roomId: $error');
      }
    }

    for (final file in files) {
      try {
        await room.sendFileEvent(
          file,
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

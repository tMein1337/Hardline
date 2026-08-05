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

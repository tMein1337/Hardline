import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

/// How long the newest event has to stay the newest before it is marked read.
///
/// Without it a burst of messages sends one receipt each. With it, a
/// conversation arriving while the room is open costs one request.
const Duration _settle = Duration(milliseconds: 800);

/// How far from the newest end of the list still counts as "looking at it".
///
/// The list is `reverse: true`, so zero pixels is the newest message. Somebody
/// who has scrolled up into history has not read what arrived underneath them,
/// and marking it read would clear a badge for something they never saw.
const double _bottomThreshold = 120.0;

/// Marks the open room read.
///
/// Nothing in this app did that before, which made the unread and mention
/// counts monotonic: `highlightCount` comes from the homeserver, and the
/// homeserver only lowers it when a read receipt moves past the events that
/// raised it. Opening the room did nothing, so every mention ever received
/// accumulated until the same account read that room in another client.
///
/// Deliberately not a provider. It is a side effect of one particular list
/// being on screen, it owns a debounce timer, and it has no state anybody
/// reads — the same reasons `TimelineController` is a plain object.
class ReadReceiptSender {
  ReadReceiptSender({required this.client, required this.roomId});

  final Client client;
  final String roomId;

  Timer? _timer;
  String? _marked;
  bool _sending = false;
  bool _disposed = false;

  /// Considers marking [eventId] read.
  ///
  /// [atBottom] is whether the list is showing the newest end. Callers pass it
  /// rather than being asked to interpret scroll metrics themselves.
  void onNewest(String? eventId, {required bool atBottom}) {
    if (_disposed || eventId == null || !atBottom) return;
    if (eventId == _marked) return;
    if (!_isVisible) return;

    _timer?.cancel();
    _timer = Timer(_settle, () => unawaited(_send(eventId)));
  }

  /// Whether the window is in a state where "on screen" means "being read".
  ///
  /// A minimised or hidden window is not being read, and silently clearing a
  /// mention that arrived while the app sat in the tray is exactly the failure
  /// this whole change exists to fix. An *unfocused but visible* window counts
  /// as read: on desktop that is a second monitor, which people do read.
  bool get _isVisible => switch (WidgetsBinding.instance.lifecycleState) {
    null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => false,
  };

  Future<void> _send(String eventId) async {
    if (_disposed || _sending || eventId == _marked) return;

    final room = client.getRoomById(roomId);
    if (room == null) return;

    // Nothing to clear. Without this, every room switch posts a receipt for an
    // event the server already knows we have read.
    if (room.notificationCount == 0 &&
        room.highlightCount == 0 &&
        !room.hasNewMessages) {
      _marked = eventId;
      return;
    }

    _sending = true;
    try {
      // Sends the fully-read marker and a receipt. `Room.setReadMarker` always
      // includes the private receipt and adds the public one when the client is
      // configured for it, which it is by default — a read receipt others can
      // see is the ordinary, expected behaviour of opening a chat.
      await room.setReadMarker(eventId, mRead: eventId);
      if (!_disposed) _marked = eventId;
    } catch (error) {
      // Same swallow-and-log as sending a message: a receipt that did not land
      // is a stale badge, not a broken room, and it will be retried by the next
      // event that arrives.
      debugPrint('Could not mark $roomId read: $error');
    } finally {
      _sending = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Whether [position] is showing the newest end of a reversed list.
bool isAtNewestEnd(ScrollPosition position) =>
    position.pixels <= _bottomThreshold;

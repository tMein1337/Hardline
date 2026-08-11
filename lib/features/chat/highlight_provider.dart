import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Take me to this message, and mark it when you get there."
///
/// The [seq] is what makes asking twice work. Without it a second request for
/// the same event compares equal to the first, `ref.listen` sees no change and
/// nothing happens — which is precisely what someone does when the first jump
/// scrolled somewhere they did not expect and they click the row again.
@immutable
class HighlightRequest {
  const HighlightRequest({
    required this.roomId,
    required this.eventId,
    required this.seq,
  });

  final String roomId;
  final String eventId;
  final int seq;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HighlightRequest &&
          roomId == other.roomId &&
          eventId == other.eventId &&
          seq == other.seq;

  @override
  int get hashCode => Object.hash(roomId, eventId, seq);
}

/// The pending jump, if any.
///
/// Deliberately a request rather than a piece of scroll state: the message list
/// is rebuilt from scratch when the room changes (it is keyed by room id), so
/// the target has to survive somewhere the list does not. `MessageList` listens
/// here and clears the request once it has acted on it.
class HighlightedEvent extends Notifier<HighlightRequest?> {
  int _seq = 0;

  @override
  HighlightRequest? build() => null;

  void request({required String roomId, required String eventId}) {
    state = HighlightRequest(roomId: roomId, eventId: eventId, seq: ++_seq);
  }

  void clear() => state = null;
}

final highlightedEventProvider =
    NotifierProvider<HighlightedEvent, HighlightRequest?>(
      HighlightedEvent.new,
    );

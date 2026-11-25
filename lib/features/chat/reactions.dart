// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// One reaction as it arrived: who reacted with what, and when.
typedef ReactionEvent = ({
  String key,
  String senderId,
  String eventId,
  DateTime timestamp,
  bool sent,
});

/// Everybody who reacted to a message with one [key].
@immutable
class ReactionSummary {
  const ReactionSummary({
    required this.key,
    required this.senderIds,
    this.myEventId,
    this.mySent = false,
  });

  /// What was reacted with — almost always an emoji, but the spec allows any
  /// text, and other clients send words.
  final String key;

  /// The people who reacted, in the order they did.
  final List<String> senderIds;

  /// Our own reaction's event id, when we are among them.
  final String? myEventId;

  /// Whether our reaction has reached the server. Until it has, its id is a
  /// transaction id that cannot be redacted.
  final bool mySent;

  int get count => senderIds.length;
  bool get mine => myEventId != null;

  @override
  bool operator ==(Object other) =>
      other is ReactionSummary &&
      key == other.key &&
      myEventId == other.myEventId &&
      mySent == other.mySent &&
      listEquals(senderIds, other.senderIds);

  @override
  int get hashCode =>
      Object.hash(key, myEventId, mySent, Object.hashAll(senderIds));
}

/// Groups [reactions] by key, in the order each key first appeared.
///
/// One person counts once per key however many events they sent for it: a
/// second identical reaction is a client bug or a race, and counting it twice
/// would let one person inflate a tally.
List<ReactionSummary> summarizeReactions(
  Iterable<ReactionEvent> reactions, {
  required String? me,
}) {
  final sorted = [...reactions]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final senders = <String, List<String>>{};
  final mine = <String, ReactionEvent>{};
  for (final reaction in sorted) {
    final list = senders.putIfAbsent(reaction.key, () => []);
    if (list.contains(reaction.senderId)) continue;
    list.add(reaction.senderId);
    if (reaction.senderId == me) mine[reaction.key] = reaction;
  }

  return [
    for (final MapEntry(:key, :value) in senders.entries)
      ReactionSummary(
        key: key,
        senderIds: List.unmodifiable(value),
        myEventId: mine[key]?.eventId,
        mySent: mine[key]?.sent ?? false,
      ),
  ];
}

/// The reactions on [original], read from the timeline's aggregation.
List<ReactionSummary> reactionsOf(Event original, Timeline timeline) {
  final events = original.aggregatedEvents(
    timeline,
    RelationshipTypes.reaction,
  );
  if (events.isEmpty) return const [];

  return summarizeReactions([
    for (final event in events)
      if (!event.redacted && event.type == EventTypes.Reaction)
        if (_keyOf(event) case final key?)
          (
            key: key,
            senderId: event.senderId,
            eventId: event.eventId,
            timestamp: event.originServerTs,
            sent: event.status.isSent,
          ),
  ], me: original.room.client.userID);
}

String? _keyOf(Event event) => event.content
    .tryGetMap<String, Object?>('m.relates_to')
    ?.tryGet<String>('key');

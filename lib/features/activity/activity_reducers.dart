// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The activity log's record type and the pure rules over it.
///
/// Split out from `message_activity_log.dart` for the same reason
/// `computeGroupingFlags` was split out of the timeline: these rules decide what
/// the summary shows, and testing them through a real `Client` would mean a
/// homeserver, a database and a sync.
library;

import 'package:flutter/foundation.dart';

/// How many characters of a message survive into a list row.
const int kPreviewLength = 140;

/// One remembered message, reduced to the facts that do not change.
///
/// Deliberately holds **no** display name, avatar or room name. Those are
/// resolved when a row is drawn, because Matrix loads room members lazily: a
/// message captured during the first sync often knows its sender only as
/// `@alice:example.org`, and freezing that into the log would leave the summary
/// showing raw ids for the rest of the session.
@immutable
class MessageRecord {
  const MessageRecord({
    required this.eventId,
    required this.roomId,
    required this.userId,
    required this.preview,
    required this.timestamp,
  });

  final String eventId;
  final String roomId;
  final String userId;

  /// One line of plain text, already collapsed and truncated — see [previewOf].
  final String preview;

  final DateTime timestamp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageRecord &&
          eventId == other.eventId &&
          roomId == other.roomId &&
          userId == other.userId &&
          preview == other.preview &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(eventId, roomId, userId, preview, timestamp);
}

/// Collapses a message body to one line of at most [kPreviewLength] characters.
///
/// Done at capture rather than at render: a multi-line paste would otherwise
/// make one row as tall as the whole section, and every widget drawing an
/// activity would have to remember to guard against it.
String previewOf(String body) {
  final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= kPreviewLength) return flat;
  return '${flat.substring(0, kPreviewLength).trimRight()}…';
}

/// Normalises the log: newest first, one entry per event, nothing stale, capped.
///
/// [horizon] is the age past which an entry is dropped entirely, which is what
/// stops the log growing without bound in a busy account. It is deliberately
/// *not* the user's "recent" window — that is applied when reading, so widening
/// the window shows more history immediately instead of needing a re-fetch.
///
/// Deduplication by event id is what lets the backfill and the live sync feed
/// the same list without the seeded `lastEvent` appearing twice.
List<MessageRecord> pruneActivities(
  Iterable<MessageRecord> entries, {
  required DateTime now,
  required Duration horizon,
  required int cap,
}) {
  final cutoff = now.subtract(horizon);

  final byEvent = <String, MessageRecord>{};
  for (final entry in entries) {
    if (entry.timestamp.isBefore(cutoff)) continue;
    byEvent[entry.eventId] = entry;
  }

  final sorted = byEvent.values.toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  return sorted.length <= cap ? sorted : sorted.sublist(0, cap);
}

/// The most recent entry for each of [userIds], within [window].
///
/// Expects [entries] newest-first, as [pruneActivities] returns it, so the first
/// hit for a user is their latest and the rest can be skipped.
Map<String, MessageRecord> newestPerUser(
  List<MessageRecord> entries,
  Set<String> userIds, {
  required DateTime now,
  required Duration window,
}) {
  if (userIds.isEmpty) return const {};
  final cutoff = now.subtract(window);

  final result = <String, MessageRecord>{};
  for (final entry in entries) {
    if (!userIds.contains(entry.userId)) continue;
    if (entry.timestamp.isBefore(cutoff)) continue;
    result.putIfAbsent(entry.userId, () => entry);
    if (result.length == userIds.length) break;
  }
  return result;
}

/// Entries by any of [userIds] inside [window], newest first, at most [cap].
List<MessageRecord> messagesOf(
  List<MessageRecord> entries,
  Set<String> userIds, {
  required DateTime now,
  required Duration window,
  required int cap,
}) {
  if (userIds.isEmpty) return const [];
  final cutoff = now.subtract(window);

  final result = <MessageRecord>[];
  for (final entry in entries) {
    if (!userIds.contains(entry.userId)) continue;
    if (entry.timestamp.isBefore(cutoff)) continue;
    result.add(entry);
    if (result.length == cap) break;
  }
  return result;
}

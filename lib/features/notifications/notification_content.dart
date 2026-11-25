// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

// What a desktop notification says, decided away from the platform plugin so
// it can be tested with plain events.

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import '../../core/util/display_name.dart';

const _localizations = MatrixDefaultLocalizations();

/// Longest body a notification carries. Every platform truncates on its own,
/// but some only after laying out the whole text, and a pasted log file
/// should not be what gets sent over D-Bus.
const _maxBody = 300;

/// One notification, ready to show.
@immutable
class NotificationContent {
  const NotificationContent({
    required this.roomId,
    required this.title,
    required this.body,
    this.eventId,
  });

  final String roomId;
  final String? eventId;
  final String title;
  final String body;

  /// The platform id: one per room, so a newer message replaces the
  /// notification for the older one instead of stacking a tower of them.
  int get id => notificationIdForRoom(roomId);

  /// What clicking it hands back: where to go.
  String get payload => eventId == null ? roomId : '$roomId|$eventId';

  @override
  bool operator ==(Object other) =>
      other is NotificationContent &&
      roomId == other.roomId &&
      eventId == other.eventId &&
      title == other.title &&
      body == other.body;

  @override
  int get hashCode => Object.hash(roomId, eventId, title, body);
}

/// A stable, positive 31-bit id for [roomId].
///
/// Not `String.hashCode`, which is allowed to differ between runs and between
/// the debug and release builds; a notification shown before a restart has to
/// be replaceable after it. FNV-1a, folded to what every platform accepts.
int notificationIdForRoom(String roomId) {
  var hash = 0x811c9dc5;
  for (final unit in roomId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Splits a payload back into (room, event).
({String roomId, String? eventId})? parseNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  final bar = payload.indexOf('|');
  if (bar < 0) return (roomId: payload, eventId: null);
  return (
    roomId: payload.substring(0, bar),
    eventId: payload.substring(bar + 1),
  );
}

/// The notification for [event], or null if it is not worth one.
///
/// With [preview] off the text of the message is never shown — only that
/// somebody wrote, and where. That is the setting for a screen other people
/// can see, and for encrypted rooms whose contents should not end up in the
/// operating system's notification history.
NotificationContent? describeNotification(
  Event event, {
  required bool preview,
}) {
  final room = event.room;
  final roomName = displaySafeName(
    room.getLocalizedDisplayname(_localizations),
    fallback: room.id,
  );

  // An invitation arrives as our own membership changing.
  if (event.type == EventTypes.RoomMember) {
    if (event.stateKey != room.client.userID) return null;
    if (event.content.tryGet<String>('membership') != 'invite') return null;
    final inviter = displaySafeName(
      event.senderFromMemoryOrFallback.calcDisplayname(),
      fallback: event.senderId,
    );
    return NotificationContent(
      roomId: room.id,
      title: roomName,
      body: '$inviter invited you',
    );
  }

  final isMessage =
      event.type == EventTypes.Message ||
      event.type == EventTypes.Encrypted ||
      event.type == EventTypes.Sticker;
  if (!isMessage || event.redacted) return null;
  // An edit is the same message again, and it was notified the first time.
  if (event.relationshipType == RelationshipTypes.edit) return null;

  final sender = displaySafeName(
    event.senderFromMemoryOrFallback.calcDisplayname(),
    fallback: event.senderId,
  );

  final String text;
  if (!preview) {
    text = 'New message';
  } else if (event.type == EventTypes.Encrypted) {
    // Arrived before its keys did. Saying so is more honest than a blank.
    text = 'Encrypted message';
  } else {
    text = event
        .calcLocalizedBodyFallback(
          _localizations,
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
        )
        .trim();
  }

  final body = room.isDirectChat ? text : '$sender: $text';

  return NotificationContent(
    roomId: room.id,
    eventId: event.eventId,
    // A direct chat is named after the person anyway; repeating the name in
    // the body would read "Alice — Alice: hi".
    title: roomName,
    body: body.length > _maxBody ? '${body.substring(0, _maxBody)}…' : body,
  );
}

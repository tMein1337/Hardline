// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/space_children.dart';
import '../../core/providers/injected_providers.dart';
import '../chat/chat_prefs.dart';
import '../shell/selection_providers.dart';
import '../spaces/space_summary.dart';
import 'desktop_notifications.dart';
import 'notification_content.dart';

/// Where notifications are shown. Overridden in tests.
final notificationSinkProvider = Provider<NotificationSink>((ref) {
  return DesktopNotifications(
    onOpen: (payload) {
      final target = parseNotificationPayload(payload);
      if (target == null) return;
      _openRoom(ref, target.roomId);
    },
  );
});

/// Whether the window is in front. On the desktop `resumed` means focused:
/// Flutter reports `inactive` as soon as another window takes focus.
final appFocusedProvider = Provider<bool Function()>(
  (ref) =>
      () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
);

/// Selects [roomId] and the space that holds it — the same two selections
/// `openRoom` in `activity_navigation.dart` makes, from a provider rather than
/// a widget.
void _openRoom(Ref ref, String roomId) {
  final spaceId =
      spaceIdOfRoom(ref.read(clientProvider), roomId) ?? kHomeSpaceId;
  ref.read(selectedSpaceIdProvider.notifier).select(spaceId);
  ref
      .read(selectedRoomIdsProvider.notifier)
      .select(spaceId: spaceId, roomId: roomId);
}

/// Whether a message in [roomId] deserves a notification right now.
///
/// The homeserver's push rules have already been applied by the time an event
/// gets here (it arrived through `Client.onNotification`), so muted rooms and
/// "mentions only" are settled. What is left is the user's own switch, and
/// not interrupting somebody who is already reading the room.
bool shouldNotify({
  required String roomId,
  required ChatPrefsState prefs,
  required bool appFocused,
  required String? openRoomId,
}) {
  if (!prefs.notify) return false;
  if (appFocused && openRoomId == roomId) return false;
  return true;
}

/// Raises a desktop notification for each event the push rules say should
/// notify, and withdraws it again once the room has been read — here or on
/// another device.
///
/// Built from `BackgroundWorkers`, so it runs from the first sync whether or
/// not any particular screen is open.
final messageNotificationsProvider = Provider<void>((ref) {
  final client = ref.watch(clientProvider);
  final sink = ref.watch(notificationSinkProvider);
  final focused = ref.watch(appFocusedProvider);

  /// Rooms with a notification showing, so a sync can withdraw the ones that
  /// were read elsewhere without asking the platform for every room.
  final showing = <String>{};

  void onEvent(Event event) {
    final roomId = event.roomId;
    if (roomId == null || event.senderId == client.userID) return;
    final prefs = ref.read(chatPrefsProvider);
    if (!shouldNotify(
      roomId: roomId,
      prefs: prefs,
      appFocused: focused(),
      openRoomId: ref.read(selectedRoomIdProvider),
    )) {
      return;
    }
    final content = describeNotification(
      event,
      preview: prefs.notificationPreview,
    );
    if (content == null) return;
    showing.add(roomId);
    unawaited(sink.show(content));
  }

  void withdraw(String roomId) {
    if (!showing.remove(roomId)) return;
    unawaited(sink.cancelRoom(roomId));
  }

  final events = client.onNotification.stream.listen(onEvent);
  final syncs = client.onSync.stream.listen((_) {
    for (final roomId in [...showing]) {
      final room = client.getRoomById(roomId);
      if (room == null ||
          (room.notificationCount == 0 &&
              room.membership != Membership.invite)) {
        withdraw(roomId);
      }
    }
  });

  // Opening the room is reading it.
  ref.listen(selectedRoomIdProvider, (_, roomId) {
    if (roomId != null) withdraw(roomId);
  });

  ref.onDispose(() {
    unawaited(events.cancel());
    unawaited(syncs.cancel());
  });
});

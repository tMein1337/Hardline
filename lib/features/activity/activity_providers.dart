// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/snapshot_list.dart';
import '../voice/matrix_rtc_membership.dart';
import '../voice/voice_expiry_tick_provider.dart';
import '../voice/voice_joinability.dart';
import 'activity_entries.dart';
import 'activity_prefs_controller.dart';
import 'activity_reducers.dart';
import 'message_activity_log.dart';
import '../../core/util/display_name.dart';

/// Most rows the message feed will draw.
///
/// A summary that needs scrolling has stopped being a summary; anything older
/// than this is reachable in the room it was said in.
const int _maxMessageRows = 30;

/// Everything the log holds, without the backfill progress.
///
/// Selected rather than watched whole so a progress tick from 3/30 to 4/30 does
/// not recompute every list.
final _recordsProvider = Provider<ListSnapshot<MessageRecord>>(
  (ref) => ref.watch(messageActivityLogProvider.select((s) => s.entries)),
);

/// Joined, non-space rooms — the only places activity can happen.
List<Room> _activeRooms(Client client) => [
  for (final room in client.rooms)
    if (!room.isSpace && room.membership == Membership.join) room,
];

/// Followed people currently sitting in a call, and where.
///
/// This is `voiceParticipantsProvider` widened from one room to all of them.
/// The "an empty state event means they left" rule that trips everyone up is
/// already handled inside `liveMembershipsOf`.
final followedVoiceActivityProvider = Provider<ListSnapshot<VoiceActivity>>((
  ref,
) {
  // Two independent reasons the answer changes: someone published or cleared a
  // membership (sync), or one aged out (wall clock).
  ref.watch(matrixTickProvider);
  ref.watch(voiceExpiryTickProvider);

  final prefs = ref.watch(activityPrefsProvider);
  if (!prefs.hasFollowing) return const ListSnapshot.empty();

  final client = ref.watch(clientProvider);

  final entries = <VoiceActivity>[];
  for (final room in _activeRooms(client)) {
    // One row per person per room: somebody connected from a phone and a
    // desktop is still one person in one channel.
    final seen = <String>{};
    for (final membership in liveMembershipsOf(room)) {
      if (!prefs.isFollowing(membership.userId)) continue;
      if (!seen.add(membership.userId)) continue;

      final user = room.unsafeGetUserFromMemoryOrFallback(membership.userId);
      entries.add(
        VoiceActivity(
          userId: membership.userId,
          displayName: displaySafeName(user.calcDisplayname()),
          avatarMxc: user.avatarUrl?.toString(),
          roomId: room.id,
          roomName: displaySafeName(room.getLocalizedDisplayname()),
          joinability: joinabilityOf(room),
        ),
      );
    }
  }

  // Sorted by name then room so the list is stable. Sorting by when they joined
  // would reshuffle on every membership heartbeat, producing an unequal
  // snapshot and repainting the page for no visible reason.
  entries.sort((a, b) {
    final byName = a.displayName.toLowerCase().compareTo(
      b.displayName.toLowerCase(),
    );
    return byName != 0 ? byName : a.roomName.compareTo(b.roomName);
  });

  return ListSnapshot(entries);
});

/// Followed people who are typing, or who spoke inside the window.
///
/// One row per person, not per room: the question is "where is Alice", and
/// three Alices answer it worse than one.
final followedActiveUsersProvider = Provider<ListSnapshot<UserActivity>>((ref) {
  // Typing arrives as an ephemeral event on the sync; the expiry tick is what
  // ages a "4 minutes ago" row out of the window in a room that has gone quiet
  // and so produces no syncs at all.
  ref.watch(matrixTickProvider);
  ref.watch(voiceExpiryTickProvider);

  final prefs = ref.watch(activityPrefsProvider);
  if (!prefs.hasFollowing) return const ListSnapshot.empty();

  final client = ref.watch(clientProvider);
  final records = ref.watch(_recordsProvider);
  final now = DateTime.now();

  // Where each followed person is typing right now, if anywhere.
  final typingIn = <String, Room>{};
  for (final room in _activeRooms(client)) {
    for (final user in room.typingUsers) {
      if (!prefs.isFollowing(user.id)) continue;
      typingIn.putIfAbsent(user.id, () => room);
    }
  }

  final spoke = newestPerUser(
    records.items,
    prefs.following,
    now: now,
    window: prefs.recentWindow,
  );

  final entries = <UserActivity>[];
  for (final userId in {...typingIn.keys, ...spoke.keys}) {
    final typingRoom = typingIn[userId];
    final record = spoke[userId];

    // Typing outranks a timestamp: where somebody is writing right now is more
    // useful than where they last finished.
    final room = typingRoom ?? client.getRoomById(record!.roomId);
    if (room == null) continue;

    final user = room.unsafeGetUserFromMemoryOrFallback(userId);
    entries.add(
      UserActivity(
        userId: userId,
        displayName: displaySafeName(user.calcDisplayname()),
        avatarMxc: user.avatarUrl?.toString(),
        roomId: room.id,
        roomName: displaySafeName(room.getLocalizedDisplayname()),
        isTyping: typingRoom != null,
        lastSpokeAt: record?.timestamp,
        lastEventId: record?.eventId,
      ),
    );
  }

  // Typists first, then most recent. Somebody mid-sentence is the most
  // actionable thing this list can report.
  entries.sort((a, b) {
    if (a.isTyping != b.isTyping) return a.isTyping ? -1 : 1;
    final at = a.lastSpokeAt;
    final bt = b.lastSpokeAt;
    if (at == null || bt == null) {
      if (at != bt) return at == null ? 1 : -1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    }
    return bt.compareTo(at);
  });

  return ListSnapshot(entries);
});

/// Individual recent messages from followed people, newest first.
final followedMessagesProvider = Provider<ListSnapshot<MessageActivity>>((ref) {
  // Room and sender names are resolved here rather than stored in the log, so
  // they follow lazily loaded members instead of freezing at capture time.
  ref.watch(matrixTickProvider);
  ref.watch(voiceExpiryTickProvider);

  final prefs = ref.watch(activityPrefsProvider);
  if (!prefs.hasFollowing || !prefs.showMessages) {
    return const ListSnapshot.empty();
  }

  final client = ref.watch(clientProvider);
  final records = ref.watch(_recordsProvider);

  final selected = messagesOf(
    records.items,
    prefs.following,
    now: DateTime.now(),
    window: prefs.recentWindow,
    cap: _maxMessageRows,
  );

  return ListSnapshot([
    for (final record in selected)
      if (client.getRoomById(record.roomId) case final room?)
        MessageActivity(
          eventId: record.eventId,
          roomId: record.roomId,
          roomName: displaySafeName(room.getLocalizedDisplayname()),
          userId: record.userId,
          displayName: displaySafeName(
            room
                .unsafeGetUserFromMemoryOrFallback(record.userId)
                .calcDisplayname(),
          ),
          avatarMxc: room
              .unsafeGetUserFromMemoryOrFallback(record.userId)
              .avatarUrl
              ?.toString(),
          preview: record.preview,
          timestamp: record.timestamp,
        ),
  ]);
});

/// Everyone in a joined room who could be followed but is not yet.
///
/// Reads `getParticipants()`, which is the in-memory member list — no request,
/// and no `await`. Lazy loading means it holds the people the SDK has actually
/// heard about, which is exactly the set worth offering.
final followCandidatesProvider = Provider<ListSnapshot<FollowCandidate>>((ref) {
  ref.watch(matrixTickProvider);

  final client = ref.watch(clientProvider);
  final prefs = ref.watch(activityPrefsProvider);
  final ownId = client.userID;

  final byId = <String, FollowCandidate>{};
  for (final room in _activeRooms(client)) {
    for (final user in room.getParticipants()) {
      if (user.id == ownId) continue;
      if (user.membership != Membership.join) continue;
      if (prefs.isFollowing(user.id)) continue;
      byId.putIfAbsent(
        user.id,
        () => FollowCandidate(
          userId: user.id,
          displayName: displaySafeName(user.calcDisplayname()),
          avatarMxc: user.avatarUrl?.toString(),
        ),
      );
    }
  }

  final entries = byId.values.toList()
    ..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
  return ListSnapshot(entries);
});

/// The people being followed, as rows the manage list can draw.
final followingProvider = Provider<ListSnapshot<FollowCandidate>>((ref) {
  ref.watch(matrixTickProvider);

  final client = ref.watch(clientProvider);
  final prefs = ref.watch(activityPrefsProvider);

  final entries = [
    for (final userId in prefs.following)
      FollowCandidate(
        userId: userId,
        displayName: _displayNameOf(client, userId),
        avatarMxc: _avatarOf(client, userId),
      ),
  ]..sort(
    (a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
  );

  return ListSnapshot(entries);
});

/// Finds a name for someone from whichever joined room knows them.
///
/// A followed person can be in several rooms or, after leaving them all, none —
/// in which case the id is the only honest thing to show.
String _displayNameOf(Client client, String userId) {
  for (final room in _activeRooms(client)) {
    final user = room.getParticipants().where((u) => u.id == userId).firstOrNull;
    if (user != null) return displaySafeName(user.calcDisplayname());
  }
  return userId;
}

String? _avatarOf(Client client, String userId) {
  for (final room in _activeRooms(client)) {
    final user = room.getParticipants().where((u) => u.id == userId).firstOrNull;
    if (user?.avatarUrl != null) return user!.avatarUrl.toString();
  }
  return null;
}

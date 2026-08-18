// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/snapshot_list.dart';
import 'matrix_rtc_membership.dart';
import 'voice_expiry_tick_provider.dart';
import 'voice_participant.dart';
import '../../core/util/display_name.dart';

/// Who is in this room's call, whether or not we have joined it.
///
/// Family-per-room, mirroring `roomHeaderProvider`, so a call starting in one
/// room does not rebuild every other room's tile.
final voiceParticipantsProvider =
    Provider.family<ListSnapshot<VoiceParticipant>, String>((ref, roomId) {
      // Two independent reasons the answer changes: someone published or
      // cleared a membership (sync), or one aged out (wall clock).
      ref.watch(matrixTickProvider);
      ref.watch(voiceExpiryTickProvider);

      final client = ref.watch(clientProvider);
      final room = client.getRoomById(roomId);
      if (room == null) return const ListSnapshot.empty();

      // One row per person: someone connected from phone and desktop is still
      // one person in the channel, and two identical rows would read as a bug.
      final byUser = <String, List<MatrixRtcMembership>>{};
      for (final membership in liveMembershipsOf(room)) {
        byUser.putIfAbsent(membership.userId, () => []).add(membership);
      }

      // Sorted by user id so the list is stable. Sorting by timestamp would
      // reshuffle on every membership refresh, producing an unequal snapshot
      // and repainting the sidebar for no visible reason.
      final userIds = byUser.keys.toList()..sort();

      return ListSnapshot([
        for (final userId in userIds)
          VoiceParticipant(
            userId: userId,
            // Sorted so the snapshot stays stable across heartbeats, for the
            // same reason the user list is sorted.
            deviceIds:
                byUser[userId]!.map((m) => m.deviceId).toSet().toList()..sort(),
            displayName: displaySafeName(
              room
                  .unsafeGetUserFromMemoryOrFallback(userId)
                  .calcDisplayname(),
            ),
            avatarMxc: room
                .unsafeGetUserFromMemoryOrFallback(userId)
                .avatarUrl
                ?.toString(),
            // Screenshare is not advertised in the membership event under
            // MatrixRTC — it is a LiveKit track publication. Only participants
            // who have joined the SFU can see it, so it stays false here and is
            // filled in from LiveKit state once we are in the call.
            isScreensharing: false,
            isSelf: userId == client.userID,
          ),
      ]);
    });

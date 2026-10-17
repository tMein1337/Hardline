// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/display_name.dart';
import 'mentions.dart';

/// Who can be mentioned in a room.
///
/// Read from the room's loaded member state rather than by calling
/// `getParticipants()`, which would fire a `/members` request the first time
/// somebody typed `@` — and typing is the worst possible moment to block on a
/// round trip. Members arrive through sync anyway, so in a room anyone has been
/// reading this is already populated.
///
/// Yourself is excluded: mentioning yourself pings yourself, which no client
/// should help anybody do by accident.
final mentionCandidatesProvider =
    Provider.family<List<MentionCandidate>, String>((ref, roomId) {
      ref.watch(matrixTickProvider);
      final client = ref.watch(clientProvider);
      final room = client.getRoomById(roomId);
      if (room == null) return const [];

      return [
        for (final user in room.getParticipants(const [Membership.join]))
          if (user.id != client.userID)
            MentionCandidate(
              userId: user.id,
              displayName: displaySafeName(
                user.calcDisplayname(),
                fallback: user.id,
              ),
              avatarMxc: user.avatarUrl?.toString(),
            ),
      ];
    });

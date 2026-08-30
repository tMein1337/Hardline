// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/matrix/room_buckets.dart';
import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/display_name.dart';

/// Rooms this client can see that both you and [userId] have joined.
///
/// **As far as this client has loaded**, which is the honest caveat and the
/// reason the dialog phrases it that way. Membership is read from room state
/// rather than from `getParticipants()`, which would mean a `/members` request
/// per room the first time somebody right-clicked a name — a dozen round trips
/// to populate one dialog.
///
/// So a room whose member list has not been fetched yet is simply not listed.
/// Under-reporting is the right direction: a name that appears is one you
/// really do share, and the count is a fact about this client's knowledge
/// rather than a claim about the server's.
final sharedRoomsProvider = Provider.family<List<String>, String>((
  ref,
  userId,
) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);
  if (userId == client.userID) return const [];

  final names = <String>[
    for (final room in joinedRoomsById(client).values)
      if (_hasJoined(room, userId))
        displaySafeName(room.getLocalizedDisplayname()),
  ]..sort();

  return names;
});

bool _hasJoined(Room room, String userId) {
  final state = room.getState(EventTypes.RoomMember, userId);
  return state?.content['membership'] == 'join';
}

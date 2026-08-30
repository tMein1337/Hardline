// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import '../../core/providers/matrix_tick_provider.dart';
import '../../core/util/display_name.dart';

/// Who is typing in one room, by display name.
///
/// Typing arrives as an ephemeral event inside the sync response, so
/// `matrixTickProvider` already covers it — there is nothing extra to
/// subscribe to, and the 120ms debounce on the tick is what keeps a room full
/// of typists from repainting the panel on every packet.
///
/// Excludes ourselves. The server echoes our own notification back, and a
/// client telling you that you are typing is a small absurdity that Element
/// also avoids.
final typingUsersProvider = Provider.family<List<String>, String>((
  ref,
  roomId,
) {
  ref.watch(matrixTickProvider);
  final client = ref.watch(clientProvider);
  final room = client.getRoomById(roomId);
  if (room == null) return const [];

  return [
    for (final user in room.typingUsers)
      if (user.id != client.userID)
        displaySafeName(user.calcDisplayname(), fallback: user.id),
  ]..sort();
});

/// The sentence shown under the timeline, or null when nobody is typing.
///
/// Named rather than counted up to three people, because "Alice is typing" is
/// worth reading and "3 people are typing" is not — but a busy room would
/// otherwise grow a line long enough to shift the composer.
String? typingSentence(List<String> names) => switch (names.length) {
  0 => null,
  1 => '${names[0]} is typing…',
  2 => '${names[0]} and ${names[1]} are typing…',
  3 => '${names[0]}, ${names[1]} and ${names[2]} are typing…',
  _ => 'Several people are typing…',
};

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

/// Loads "hero" members so direct chats can show a real name.
///
/// A DM usually has no `m.room.name`; the SDK falls back to the other
/// participants, but only once they have been loaded. `loadHeroUsers()` fetches
/// them.
///
/// The `_attempted` set is load-bearing, not an optimisation. Loading heroes
/// mutates the store, which produces a tick, which recomputes the room list,
/// which would call this again — an unbounded loop burning CPU forever. Each
/// room is therefore attempted exactly once per app run.
class HeroLoader {
  final Set<String> _attempted = {};

  void ensureLoaded(Iterable<Room> rooms) {
    for (final room in rooms) {
      // add() returns false if it was already present.
      if (_attempted.add(room.id)) _load(room);
    }
  }

  Future<void> _load(Room room) async {
    try {
      await room.loadHeroUsers();
    } catch (error) {
      // Not worth surfacing: the room simply keeps its fallback name.
      debugPrint('Could not load heroes for ${room.id}: $error');
    }
  }
}

final heroLoaderProvider = Provider<HeroLoader>((ref) => HeroLoader());

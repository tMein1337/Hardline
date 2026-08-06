import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How often expiry-sensitive derivations are re-evaluated.
///
/// A ghost participant lingers at most this long past their expiry. The work
/// per tick is a walk of one room's state map, which is nothing.
const _sweepInterval = Duration(seconds: 30);

/// Ticks on wall-clock time so call memberships can expire.
///
/// `matrixTickProvider` is not enough on its own here. `CallMembership.isExpired`
/// compares a timestamp against `DateTime.now()`, and participants refresh that
/// timestamp every two minutes while they are connected. When a client dies
/// without leaving — force quit, crash, lost power — nothing further arrives
/// over sync for that room, so the tick never fires again and the room list
/// would show that person as still in the call forever.
///
/// This is the only timer-driven provider in the app; everything else is
/// event-driven. That is a deliberate exception, not an oversight.
class VoiceExpiryTick extends Notifier<int> {
  @override
  int build() {
    final timer = Timer.periodic(_sweepInterval, (_) => state = state + 1);
    ref.onDispose(timer.cancel);
    return 0;
  }
}

/// Auto-dispose so a widget test that never mounts the room list does not fail
/// with a pending timer.
final voiceExpiryTickProvider = NotifierProvider<VoiceExpiryTick, int>(
  VoiceExpiryTick.new,
  isAutoDispose: true,
);

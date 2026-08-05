import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'injected_providers.dart';

/// Coalescing window: events arriving closer together than this are merged.
const _debounceWindow = Duration(milliseconds: 120);

/// Longest we will hold an update back.
///
/// Not optional. A pure trailing debounce starves during an initial sync — the
/// stream never goes quiet for 120ms, the timer keeps getting reset, and the
/// room list stays empty for the whole sync.
const _maxWait = Duration(milliseconds: 500);

/// A meaningless, monotonically increasing integer that ticks whenever the
/// Matrix store may have changed.
///
/// This is the *only* place SDK streams feed Riverpod list data. Everything
/// else derives immutable snapshots from `client` and watches this counter to
/// know when to recompute. Two reasons for the indirection:
///
///  * `SyncUpdate` has no value equality, so surfacing it directly would make
///    every consumer rebuild on every sync. An `int` compares cheaply.
///  * Sync traffic is noisy — typing notifications, read receipts and presence
///    all arrive as syncs. Debouncing here means one recompute per burst
///    instead of one per event.
class MatrixTick extends Notifier<int> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _debounce;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  int build() {
    final client = ref.watch(clientProvider);

    _subscriptions.addAll([
      client.onSync.stream.listen((_) => _schedule()),
      client.onRoomState.stream.listen((_) => _schedule()),
      client.onLoginStateChanged.stream.listen((_) => _schedule()),
    ]);

    ref.onDispose(() {
      _debounce?.cancel();
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
    });

    return 0;
  }

  void _schedule() {
    // Max-wait: if we have been silent long enough, emit now rather than
    // adding latency to an isolated event.
    if (DateTime.now().difference(_lastEmit) > _maxWait) {
      _emit();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, _emit);
  }

  void _emit() {
    _debounce?.cancel();
    _debounce = null;
    _lastEmit = DateTime.now();
    state = state + 1;
  }
}

final matrixTickProvider = NotifierProvider<MatrixTick, int>(MatrixTick.new);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../matrix/seeded_stream.dart';
import 'injected_providers.dart';

/// Connection state, for the "Connecting…" indicator.
///
/// Seeded, like every SDK stream surfaced to the UI — see `seeded_stream.dart`.
final syncStatusProvider = StreamProvider<SyncStatusUpdate>((ref) {
  final client = ref.watch(clientProvider);
  return seededStream(client.onSyncStatus.stream, client.onSyncStatus.value);
});

/// True while the client is not in a healthy synced state.
final isReconnectingProvider = Provider<bool>((ref) {
  return ref
      .watch(syncStatusProvider)
      .maybeWhen(
        data: (update) => update.status == SyncStatus.error,
        orElse: () => false,
      );
});

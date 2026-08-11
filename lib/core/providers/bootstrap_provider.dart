import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../features/accounts/active_client.dart';

/// Guards against `Client.init()` running twice **for the same client**.
///
/// `init()` throws `ClientInitPreconditionError` if re-entered, and a hot
/// reload preserves the isolate — so a provider rebuild could otherwise call it
/// a second time. The guard lives at module level rather than in provider state
/// precisely so it survives those rebuilds.
///
/// Keyed by client name, not global: adding a second account means a second
/// client, on its own database, that has never been initialised. A single flag
/// would report that one as already done and leave it unsynced. Client names
/// are unique per account by construction — see `matrix_bootstrap.dart`.
final Map<String, Future<void>> _initFutures = {};

Future<void> _initClientOnce(Client client) {
  final inFlight = _initFutures[client.clientName];
  if (inFlight != null) return inFlight;

  final future = _runInit(client);
  _initFutures[client.clientName] = future;
  return future;
}

Future<void> _runInit(Client client) async {
  try {
    // Restores the stored session and starts syncing. We do not wait for the
    // first network sync: cached rooms are enough to render the shell, and
    // blocking here would show a splash for the length of a round trip.
    await client.init(waitForFirstSync: false);
  } catch (_) {
    // Clear the guard so Retry actually retries. The SDK releases its own
    // internal lock in a finally block, so calling init() again is safe.
    _initFutures.remove(client.clientName);
    rethrow;
  }
}

/// Restores the previous session, if any.
///
/// Separated from client construction because this is the slow, failure-prone
/// part — it needs a splash screen and a retry affordance, whereas building the
/// client cannot meaningfully fail.
///
/// Deliberately watches the **boot** client rather than `clientProvider`: a
/// client swapped in by an account switch has already been initialised by
/// `ActiveClientController`, and re-entering `init()` on it would throw
/// `ClientInitPreconditionError` and drop the whole app to its error screen.
final bootstrapProvider = FutureProvider<void>((ref) async {
  await _initClientOnce(ref.watch(bootClientProvider).client);
});

/// Test-only: forget that init has run.
@visibleForTesting
void resetBootstrapGuard() => _initFutures.clear();

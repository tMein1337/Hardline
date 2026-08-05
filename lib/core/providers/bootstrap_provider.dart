import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import 'injected_providers.dart';

/// Guards against `Client.init()` running twice.
///
/// `init()` throws `ClientInitPreconditionError` if re-entered, and a hot
/// reload preserves the isolate — so a provider rebuild could otherwise call it
/// a second time. The guard lives at module level rather than in provider state
/// precisely so it survives those rebuilds.
Future<void>? _initFuture;

Future<void> _initClientOnce(Client client) {
  final inFlight = _initFuture;
  if (inFlight != null) return inFlight;

  final future = _runInit(client);
  _initFuture = future;
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
    _initFuture = null;
    rethrow;
  }
}

/// Restores the previous session, if any.
///
/// Separated from client construction because this is the slow, failure-prone
/// part — it needs a splash screen and a retry affordance, whereas building the
/// client cannot meaningfully fail.
final bootstrapProvider = FutureProvider<void>((ref) async {
  await _initClientOnce(ref.watch(clientProvider));
});

/// Test-only: forget that init has run.
@visibleForTesting
void resetBootstrapGuard() => _initFuture = null;

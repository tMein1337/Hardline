import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import 'injected_providers.dart';

/// The signed-in user's own display name and avatar, for the sidebar footer.
///
/// Not tied to the sync tick: a profile change is rare and the fetch hits the
/// network, so recomputing it on every sync would be wasteful.
final ownProfileProvider = FutureProvider<Profile?>((ref) async {
  final client = ref.watch(clientProvider);
  if (client.userID == null) return null;
  try {
    return await client.fetchOwnProfile();
  } catch (_) {
    // Falls back to rendering the user id.
    return null;
  }
});

/// The full Matrix id, e.g. `@alice:example.org`.
final ownUserIdProvider = Provider<String>(
  (ref) => ref.watch(clientProvider).userID ?? '',
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/login_state_provider.dart';
import '../../core/providers/own_profile_provider.dart';
import 'account_actions.dart';

/// Keeps the account list honest about whoever is actually signed in.
///
/// Two cases need this and neither goes through the add-account flow: an
/// installation that predates the account list (already logged in, nothing
/// registered) and the very first login on a fresh install. Both look the same
/// from here — a live session whose storage key has no entry — so both are
/// handled by the same write.
///
/// It also refreshes the cached display name and avatar, which is what lets the
/// account switcher draw a row for an account whose client is not running.
///
/// Watch it from something long-lived; it does nothing until read.
final accountSyncProvider = Provider<void>((ref) {
  if (!ref.watch(isLoggedInProvider)) return;
  final profile = ref.watch(ownProfileProvider).value;

  // Deferred by a microtask because a provider may not modify another provider
  // while it is building. Nothing here is urgent — it only has to happen before
  // the user opens the account switcher.
  Future.microtask(() {
    if (!ref.mounted) return;
    ref
        .read(accountActionsProvider.notifier)
        .adoptCurrentSession(
          displayName: profile?.displayName,
          avatarUrl: profile?.avatarUrl?.toString(),
        );
  });
});

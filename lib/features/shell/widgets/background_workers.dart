import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/message_activity_log.dart';
import '../../voice/stale_membership_sweeper.dart';
import '../../voice/stale_ring_sweeper.dart';

/// The work that has to happen whether or not anyone is looking at it.
///
/// Zero-sized, and sits in the shell so all of these are running from the
/// first sync rather than from whenever their screen is first opened.
///
/// Two different subscriptions, because they want different things:
///
///  * The **activity log** is `ref.listen` — it must be built and stay built,
///    but nothing here draws its contents, and watching it would rebuild this
///    widget on every message in every room.
///  * The **sweeps** are `ref.watch` — the whole point is to re-run them when
///    the clock or the sync moves, and rebuilding a `SizedBox.shrink()` is
///    free. Both sweepers throttle themselves.
///
/// The two sweeps clean up after opposite halves of a call that ended badly:
/// `stale_ring_sweeper.dart` clears the unread badge a dead ring left behind,
/// `stale_membership_sweeper.dart` withdraws a membership this device was
/// killed before it could withdraw itself.
class BackgroundWorkers extends ConsumerWidget {
  const BackgroundWorkers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(messageActivityLogProvider, (_, _) {});
    ref.watch(staleRingSweepProvider);
    ref.watch(staleMembershipSweepProvider);
    return const SizedBox.shrink();
  }
}

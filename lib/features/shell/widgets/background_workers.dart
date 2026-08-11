import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/message_activity_log.dart';
import '../../voice/stale_ring_sweeper.dart';

/// The work that has to happen whether or not anyone is looking at it.
///
/// Zero-sized, and sits in the shell so both of these are running from the
/// first sync rather than from whenever their screen is first opened.
///
/// Two different subscriptions, because they want different things:
///
///  * The **activity log** is `ref.listen` — it must be built and stay built,
///    but nothing here draws its contents, and watching it would rebuild this
///    widget on every message in every room.
///  * The **stale ring sweep** is `ref.watch` — the whole point is to re-run it
///    when the clock or the sync moves, and rebuilding a `SizedBox.shrink()` is
///    free. The sweeper throttles itself; see `stale_ring_sweeper.dart`.
class BackgroundWorkers extends ConsumerWidget {
  const BackgroundWorkers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(messageActivityLogProvider, (_, _) {});
    ref.watch(staleRingSweepProvider);
    return const SizedBox.shrink();
  }
}

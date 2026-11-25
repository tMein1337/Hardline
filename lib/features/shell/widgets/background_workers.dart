// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../activity/message_activity_log.dart';
import '../../hotkeys/hotkey_provider.dart';
import '../../notifications/message_notifications.dart';
import '../../overlay/overlay_provider.dart';
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
///
/// The **overlay driver** is here for the same reason the sweeps are: the
/// overlay has to follow a call whether or not anybody has opened its
/// settings. The **hotkey driver** likewise — every global chord, the
/// overlay's two included, has to be bound before the pane that describes it
/// has ever been visited. **Desktop notifications** too: a message has to be
/// announced whether or not its room, or any room, is on screen.
class BackgroundWorkers extends ConsumerWidget {
  const BackgroundWorkers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(messageActivityLogProvider, (_, _) {});
    ref.watch(staleRingSweepProvider);
    ref.watch(staleMembershipSweepProvider);
    ref.watch(overlayDriverProvider);
    ref.watch(hotkeyDriverProvider);
    ref.watch(messageNotificationsProvider);
    return const SizedBox.shrink();
  }
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/accounts/active_client.dart';

/// Loaded once in `main()` and injected via `ProviderScope.overrides`, so the
/// theme and the account list can be read synchronously and the very first
/// frame is already correct.
///
/// Throws if read without an override, so a missing override fails loudly at
/// startup instead of silently producing a second instance.
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw StateError(
    'prefsProvider was read without an override. It must be provided in '
    'ProviderScope(overrides: [...]) in main().',
  ),
);

/// The Matrix SDK client of the account currently signed in.
///
/// This used to be an override, on the reasoning that an override cannot be
/// rebuilt and therefore could not accidentally construct a second `Client` on
/// the same database. Multi-account made the client genuinely mutable, so that
/// guarantee moved to `ActiveClientController`, which is now the only thing
/// allowed to build or dispose one. See `active_client.dart`.
///
/// Consequences for readers, unchanged from before except the last:
///
///  * Long-lived and mutable; see the rules in `matrix_tick_provider.dart`
///    before reading it inside a widget.
///  * `watch` this, do not cache it. Switching accounts replaces the instance,
///    and anything holding the old one is holding a disposed client.
final clientProvider = Provider<Client>(
  (ref) => ref.watch(activeClientProvider).client,
);

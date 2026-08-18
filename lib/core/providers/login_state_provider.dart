// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../matrix/seeded_stream.dart';
import 'injected_providers.dart';

/// The SDK's login state.
///
/// Seeded from the controller's cached value — without that this would never
/// leave `AsyncLoading` for a restored session, because `loggedIn` is emitted
/// during `Client.init()`, before this provider exists. See `seeded_stream.dart`.
final loginStateProvider = StreamProvider<LoginState>((ref) {
  final client = ref.watch(clientProvider);
  return seededStream(
    client.onLoginStateChanged.stream,
    client.onLoginStateChanged.value,
  );
});

/// Collapsed to a bool so the router does not rebuild on state churn that does
/// not change whether we are logged in.
final isLoggedInProvider = Provider<bool>((ref) {
  final client = ref.watch(clientProvider);
  return ref
      .watch(loginStateProvider)
      .maybeWhen(
        data: (state) => state == LoginState.loggedIn,
        // Before the first event arrives, fall back to the synchronous check
        // (`accessToken != null`) rather than showing a spinner.
        orElse: () => client.isLogged(),
      );
});

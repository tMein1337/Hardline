// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../bootstrap/matrix_bootstrap.dart';

/// The live [Client] and the account whose database it has open.
///
/// The two travel together because almost every account operation needs both:
/// the client to talk to the homeserver, the key to name what is on disk.
@immutable
class ActiveClient {
  const ActiveClient({required this.client, required this.storageKey});

  final Client client;
  final String storageKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActiveClient &&
          identical(client, other.client) &&
          storageKey == other.storageKey;

  @override
  int get hashCode => Object.hash(identityHashCode(client), storageKey);
}

/// The client built in `main()`, injected via `ProviderScope.overrides`.
///
/// Built imperatively before `runApp` because the boot sequence has hard
/// ordering (vodozemac before `Client`, sqflite ffi before opening the
/// database) and because the first frame should already be looking at the right
/// account rather than at a spinner.
final bootClientProvider = Provider<ActiveClient>(
  (ref) => throw StateError(
    'bootClientProvider was read without an override. It must be provided in '
    'ProviderScope(overrides: [...]) in main().',
  ),
);

/// Whether `vodozemac` initialised. When false the client still works, but
/// encrypted rooms cannot be decrypted and verification is unavailable.
final encryptionAvailableProvider = Provider<bool>(
  (ref) => throw StateError(
    'encryptionAvailableProvider was read without an override. It must be '
    'provided in ProviderScope(overrides: [...]) in main().',
  ),
);

/// Sole owner of live [Client] instances.
///
/// The invariant this enforces used to be structural — `clientProvider` was an
/// override, and an override cannot be rebuilt, so a second client could not
/// come into existence. Multi-account needs the client to change, so the
/// guarantee moved here: **one controller constructs and disposes every client,
/// and no two live clients share a storage key.** Two clients on one key would
/// open two sqlite handles on the same file.
///
/// Nothing else should call `buildMatrixClient` or `Client.dispose`.
class ActiveClientController extends Notifier<ActiveClient> {
  @override
  ActiveClient build() => ref.watch(bootClientProvider);

  /// Opens [storageKey]'s account and makes it the live one.
  ///
  /// The new client is built and initialised **before** the old one is thrown
  /// away, and only published once it is ready. Two clients briefly coexist,
  /// which is safe precisely because they are on different databases — and it
  /// means a homeserver that is down leaves the user on the account they had
  /// instead of on nothing.
  ///
  /// The caller is responsible for leaving any running call first; see
  /// `account_actions.dart` for why that cannot happen here.
  Future<void> swapTo(String storageKey) async {
    final previous = state;
    if (previous.storageKey == storageKey) return;

    final next = await buildMatrixClient(
      encryptionAvailable: ref.read(encryptionAvailableProvider),
      storageKey: storageKey,
    );

    try {
      await next.init(waitForFirstSync: false);
    } catch (_) {
      // Never leak a half-built client: without this the storage key stays
      // occupied by a dead handle and the next attempt to open the same account
      // fails on a locked database.
      await next.dispose();
      rethrow;
    }

    state = ActiveClient(client: next, storageKey: storageKey);

    // Not `logout()`: that clears the store, which would turn switching away
    // from an account into signing out of it.
    await previous.client.dispose();
  }

  /// Replaces the live client with one that has just been logged into.
  ///
  /// Used when adding an account: the login already had to happen against a
  /// client this controller did not build, because there is nothing to
  /// authenticate against until the user has typed a homeserver.
  Future<void> adopt(Client client, String storageKey) async {
    final previous = state;
    if (identical(previous.client, client)) return;

    state = ActiveClient(client: client, storageKey: storageKey);
    await previous.client.dispose();
  }
}

final activeClientProvider =
    NotifierProvider<ActiveClientController, ActiveClient>(
      ActiveClientController.new,
    );

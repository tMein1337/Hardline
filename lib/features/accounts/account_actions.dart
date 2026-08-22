// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../bootstrap/matrix_bootstrap.dart';
import '../auth/login_controller.dart';
import '../settings/device_encryption.dart';
import '../shell/selection_providers.dart';
import '../voice/call_controller_provider.dart';
import 'account_entry.dart';
import 'account_registry.dart';
import 'active_client.dart';

/// How long a call teardown may hold up an account switch.
///
/// Bounded for the same reason the exit hook is: a hung network must never
/// leave someone stuck. Losing the race only means our membership expires on
/// its own instead of being withdrawn.
const _leaveTimeout = Duration(seconds: 3);

/// A client that has been built for an account that does not exist yet.
///
/// Adding an account needs somewhere to log in *to* before anything is known
/// about the user, so the database is created first and only becomes a
/// registered account once the login succeeds.
@immutable
class PendingLogin {
  const PendingLogin({required this.client, required this.storageKey});

  final Client client;
  final String storageKey;
}

@immutable
class AccountActionState {
  const AccountActionState({this.busy = false, this.message, this.error});

  /// Blocks the shell and shows a splash. Switching accounts tears down every
  /// provider that reads the client; letting the user click during that is
  /// asking for a request against a disposed client.
  final bool busy;

  /// What is happening, for the splash.
  final String? message;

  final String? error;

  AccountActionState copyWith({
    bool? busy,
    String? message,
    String? error,
    bool clearError = false,
  }) => AccountActionState(
    busy: busy ?? this.busy,
    message: message ?? this.message,
    error: clearError ? null : error ?? this.error,
  );
}

/// Everything that changes *which* account is signed in.
///
/// Sits above `ActiveClientController` rather than inside it because these
/// operations have to touch things the client layer must not know about — the
/// live call, the room selection, the registry. Keeping the controller ignorant
/// of them is what stops it from becoming the place every feature reaches into.
class AccountActions extends Notifier<AccountActionState> {
  @override
  AccountActionState build() => const AccountActionState();

  /// Opens another remembered account.
  Future<void> switchTo(String storageKey) async {
    if (state.busy) return;
    final target = ref.read(accountRegistryProvider).byKey(storageKey);
    if (target == null) return;
    if (ref.read(activeClientProvider).storageKey == storageKey) return;

    state = AccountActionState(busy: true, message: 'Opening ${target.label}…');
    try {
      await _leaveCall();
      await ref.read(activeClientProvider.notifier).swapTo(storageKey);
      await ref.read(accountRegistryProvider.notifier).setActive(storageKey);
      _resetSelection();
      state = const AccountActionState();
    } catch (error) {
      // The swap either happened completely or not at all, so there is a
      // working account either way — this only has to be reportable.
      state = AccountActionState(error: describeAuthError(error));
    }
  }

  /// Creates the database an added account will live in, and returns a client
  /// pointed at it for the login screen to use.
  ///
  /// Not initialised: a fresh database has no session to restore, and `login()`
  /// runs `init()` itself.
  Future<PendingLogin> beginAddAccount() async {
    final storageKey = generateStorageKey();
    final client = await buildMatrixClient(
      encryptionAvailable: ref.read(encryptionAvailableProvider),
      storageKey: storageKey,
      // A store created while this device is encrypted is created encrypted.
      // There is no moment where the new account's database exists in the clear
      // and is tidied up afterwards.
      storePassphrase: ref.read(devicePassphraseProvider),
    );
    return PendingLogin(client: client, storageKey: storageKey);
  }

  /// Throws away a login that was started and abandoned.
  ///
  /// Deleting the storage matters: an abandoned attempt otherwise leaves an
  /// orphan database behind on every cancelled "Add account".
  Future<void> cancelAddAccount(PendingLogin pending) async {
    await pending.client.dispose();
    await deleteAccountStorage(pending.storageKey);
  }

  /// Promotes a successful "Add account" login to the live account.
  Future<void> completeAddAccount(PendingLogin pending) async {
    final userId = pending.client.userID;
    if (userId == null) {
      await cancelAddAccount(pending);
      return;
    }

    state = const AccountActionState(busy: true, message: 'Signing in…');
    try {
      await _leaveCall();
      await ref
          .read(accountRegistryProvider.notifier)
          .upsert(
            AccountEntry(
              storageKey: pending.storageKey,
              userId: userId,
              homeserver: pending.client.homeserver?.host ?? '',
            ),
          );
      await ref
          .read(activeClientProvider.notifier)
          .adopt(pending.client, pending.storageKey);
      await ref
          .read(accountRegistryProvider.notifier)
          .setActive(pending.storageKey);
      _resetSelection();
      state = const AccountActionState();
    } catch (error) {
      state = AccountActionState(error: describeAuthError(error));
    }
  }

  /// Registers the session the app booted with.
  ///
  /// Needed for two cases that both look like "logged in but not listed": an
  /// installation that predates the account list, and the very first login,
  /// which happens on the boot client rather than through [completeAddAccount].
  Future<void> adoptCurrentSession({
    String? displayName,
    String? avatarUrl,
  }) async {
    final active = ref.read(activeClientProvider);
    final userId = active.client.userID;
    if (userId == null) return;

    final registry = ref.read(accountRegistryProvider);
    final existing = registry.byKey(active.storageKey);

    if (existing == null) {
      await ref
          .read(accountRegistryProvider.notifier)
          .upsert(
            AccountEntry(
              storageKey: active.storageKey,
              userId: userId,
              homeserver: active.client.homeserver?.host ?? '',
              displayName: displayName,
              avatarUrl: avatarUrl,
            ),
          );
      await ref
          .read(accountRegistryProvider.notifier)
          .setActive(active.storageKey);
      return;
    }

    await ref
        .read(accountRegistryProvider.notifier)
        .refreshProfile(
          active.storageKey,
          displayName: displayName,
          avatarUrl: avatarUrl,
        );
  }

  /// Signs out of the account currently open.
  ///
  /// When another account remains, the app moves to it rather than dropping to
  /// the login screen — being signed out of one of several accounts should not
  /// look like being signed out altogether.
  Future<void> signOutActive() async {
    if (state.busy) return;
    final active = ref.read(activeClientProvider);
    final remaining = [
      for (final entry in ref.read(accountRegistryProvider).entries)
        if (entry.storageKey != active.storageKey) entry,
    ];

    state = const AccountActionState(busy: true, message: 'Signing out…');
    try {
      await _leaveCall();
      try {
        await active.client.logout();
      } catch (error) {
        // logout() clears local state in a finally block even when the server
        // call fails, so the session is gone either way.
        debugPrint('Logout request failed, session cleared locally: $error');
      }
      await ref.read(accountRegistryProvider.notifier).remove(active.storageKey);

      if (remaining.isEmpty) {
        // Keep the client: `logout()` clears it but does not dispose it, and
        // the login screen needs something to sign in with. Its database is
        // already empty, so nothing of the old session is left on disk.
        _resetSelection();
        state = const AccountActionState();
        return;
      }

      await ref
          .read(activeClientProvider.notifier)
          .swapTo(remaining.first.storageKey);
      await ref
          .read(accountRegistryProvider.notifier)
          .setActive(remaining.first.storageKey);
      // Only safe now that nothing holds the file open.
      await deleteAccountStorage(active.storageKey);
      _resetSelection();
      state = const AccountActionState();
    } catch (error) {
      state = AccountActionState(error: describeAuthError(error));
    }
  }

  /// Signs out of an account that is not the live one.
  ///
  /// Its session lives in a database nothing has open, so this borrows a client
  /// long enough to send the logout — otherwise the account would disappear
  /// from this machine while remaining a live session on the homeserver, which
  /// is precisely the thing someone signing out is trying to prevent.
  Future<void> signOutOther(String storageKey) async {
    if (state.busy) return;
    if (ref.read(activeClientProvider).storageKey == storageKey) {
      return signOutActive();
    }
    final entry = ref.read(accountRegistryProvider).byKey(storageKey);
    if (entry == null) return;

    state = AccountActionState(
      busy: true,
      message: 'Signing out of ${entry.label}…',
    );
    try {
      final client = await buildMatrixClient(
        encryptionAvailable: ref.read(encryptionAvailableProvider),
        storageKey: storageKey,
        storePassphrase: ref.read(devicePassphraseProvider),
      );
      try {
        await client.init(waitForFirstSync: false);
        await client.logout();
      } catch (error) {
        debugPrint('Remote sign-out of ${entry.userId} failed: $error');
      } finally {
        await client.dispose();
      }

      await ref.read(accountRegistryProvider.notifier).remove(storageKey);
      await deleteAccountStorage(storageKey);
      state = const AccountActionState();
    } catch (error) {
      state = AccountActionState(error: describeAuthError(error));
    }
  }

  void dismissError() => state = state.copyWith(clearError: true);

  /// Withdraws the MatrixRTC membership before the client that published it
  /// goes away.
  ///
  /// This cannot be left to provider disposal: swapping the client rebuilds
  /// `callControllerProvider`, and `LiveKitCallController.dispose` only fires
  /// `unawaited(_teardown(...))` — which would race the old client's teardown
  /// and leave us advertised in a channel we are not in for hours.
  Future<void> _leaveCall() => ref
      .read(callControllerProvider)
      .leave()
      .timeout(_leaveTimeout, onTimeout: () {});

  /// Room and space selections name rooms of the account being left.
  void _resetSelection() {
    ref.invalidate(selectedRoomIdsProvider);
    ref.invalidate(selectedSpaceIdProvider);
  }
}

final accountActionsProvider =
    NotifierProvider<AccountActions, AccountActionState>(AccountActions.new);

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bootstrap/matrix_bootstrap.dart';
import '../../core/storage/hardline_store.dart';
import '../../core/storage/store_cipher.dart';
import '../accounts/account_registry.dart';
import '../accounts/active_client.dart';

// Turning the encryption of this installation's stores on, off, and over to a
// different passphrase.
//
// There is no preference recording whether encryption is on. The stores
// themselves are the record — `storeIsEncrypted` reads the file header — and
// `main()` asks them before it asks the user for anything. A flag in
// preferences could disagree with the disk, and both ways it could disagree are
// bad: an app that will not open a store it could have opened, and an app that
// believes it is encrypting when it is not.
//
// At runtime the question is simpler still. If this session holds a passphrase,
// the stores are keyed with it; if it holds null, they are plain files.

/// The passphrase `main()` verified against the boot account's store, or null.
///
/// Injected rather than derived, for the same reason `bootClientProvider` is:
/// the answer is settled before `runApp`, by code that had to run before there
/// were providers to ask.
final bootPassphraseProvider = Provider<String?>(
  (ref) => throw StateError(
    'bootPassphraseProvider was read without an override. It must be provided '
    'in ProviderScope(overrides: [...]) in main().',
  ),
);

/// The passphrase every store in this installation is currently keyed with.
///
/// Null means they are not encrypted. Lives in memory only, and deliberately:
/// the point of the feature is that the key is not on the disk it protects.
/// Anything that opens a store — an account switch, an added account, a
/// sign-out of an account that is not live — reads this first.
class DevicePassphrase extends Notifier<String?> {
  @override
  String? build() => ref.watch(bootPassphraseProvider);

  /// Only [DeviceEncryptionController] should call this, and only once every
  /// store has actually moved. Setting it otherwise would leave the app certain
  /// of a key that opens nothing.
  void hold(String? passphrase) => state = passphrase;
}

final devicePassphraseProvider = NotifierProvider<DevicePassphrase, String?>(
  DevicePassphrase.new,
);

/// Whether the stores on this device are encrypted.
final deviceEncryptionEnabledProvider = Provider<bool>(
  (ref) => ref.watch(devicePassphraseProvider) != null,
);

/// The shortest passphrase the settings pane will accept.
///
/// Picked to stop a two-character passphrase, not to imply that twelve
/// characters is a security boundary. SQLite3MultipleCiphers derives the key
/// with PBKDF2 over a per-database salt, which slows guessing down; it does not
/// make a guessable passphrase unguessable.
const kMinPassphraseLength = 12;

@immutable
class DeviceEncryptionState {
  const DeviceEncryptionState({this.busy = false, this.message, this.error});

  final bool busy;

  /// What is happening, while it is happening. Re-keying rewrites every page of
  /// every store, which on a large account takes long enough to look like a
  /// hang if nothing says otherwise.
  final String? message;
  final String? error;
}

class DeviceEncryptionController extends Notifier<DeviceEncryptionState> {
  @override
  DeviceEncryptionState build() => const DeviceEncryptionState();

  /// Encrypts every store on this device with [passphrase].
  Future<bool> enable(String passphrase) =>
      _move(from: null, to: passphrase, verb: 'Encrypting');

  /// Decrypts every store back to a plain SQLite file.
  Future<bool> disable() => _move(
    from: ref.read(devicePassphraseProvider),
    to: null,
    verb: 'Decrypting',
  );

  /// Re-keys every store from the current passphrase to [passphrase].
  Future<bool> changePassphrase(String passphrase) => _move(
    from: ref.read(devicePassphraseProvider),
    to: passphrase,
    verb: 'Changing the passphrase for',
  );

  void dismissError() =>
      state = DeviceEncryptionState(busy: state.busy, message: state.message);

  /// Moves every store from one key to another.
  ///
  /// The live account is re-keyed through the connection the SDK is already
  /// using: `PRAGMA rekey` rewrites the file underneath a connection that stays
  /// open, so nothing is closed and no client is rebuilt. The others are
  /// opened, moved and closed one at a time.
  ///
  /// **Every store moves or none does.** A half-done change is the worst
  /// outcome available here — the app would hold one passphrase while some
  /// accounts were still on the other, and nobody would find out until they
  /// switched to one of those and met a store it could not open. So a run that
  /// fails part-way puts the finished ones back before reporting.
  Future<bool> _move({
    required String? from,
    required String? to,
    required String verb,
  }) async {
    if (state.busy) return false;

    final active = ref.read(activeClientProvider);
    final store = active.client.database;
    if (store is! HardlineStore) {
      state = const DeviceEncryptionState(
        error: 'This account is not on a store Hardline can re-key.',
      );
      return false;
    }

    // The registry is the list of accounts, but the live one is not always in
    // it: a first-ever launch runs on the default storage key before anything
    // has been registered.
    final keys = <String>{
      active.storageKey,
      ...ref.read(accountRegistryProvider).entries.map((e) => e.storageKey),
    };

    state = DeviceEncryptionState(
      busy: true,
      message: keys.length == 1
          ? '$verb the store…'
          : '$verb ${keys.length} stores…',
    );

    final moved = <String>[];
    try {
      await rekeyOpenStore(store.connection, to);
      moved.add(active.storageKey);

      for (final key in keys.where((k) => k != active.storageKey)) {
        await rekeyStoreAt(
          path: await accountStorePath(key),
          from: from,
          to: to,
        );
        moved.add(key);
      }

      ref.read(devicePassphraseProvider.notifier).hold(to);
      state = const DeviceEncryptionState();
      return true;
    } catch (error, stack) {
      debugPrint('Re-keying the stores failed: $error\n$stack');
      await _rollBack(moved, store, from: from, to: to);
      state = DeviceEncryptionState(error: _describe(error));
      return false;
    }
  }

  /// Puts the stores that did move back where they came from.
  ///
  /// Best-effort by necessity: if this fails too, the disk is in a state no
  /// amount of further writing will improve. It is logged rather than thrown so
  /// that what reaches the user is the failure they caused, not the one it
  /// caused in turn.
  Future<void> _rollBack(
    List<String> moved,
    HardlineStore store, {
    required String? from,
    required String? to,
  }) async {
    final activeKey = ref.read(activeClientProvider).storageKey;
    for (final key in moved) {
      try {
        if (key == activeKey) {
          await rekeyOpenStore(store.connection, from);
        } else {
          await rekeyStoreAt(
            path: await accountStorePath(key),
            from: to,
            to: from,
          );
        }
      } catch (error) {
        debugPrint('Could not put $key back: $error');
      }
    }
  }

  String _describe(Object error) => switch (error) {
    StoreCipherUnavailable() =>
      'This build of Hardline has no encryption in its SQLite library, so it '
          'will not pretend to encrypt anything. Nothing was changed.',
    WrongStorePassphrase() =>
      'One of the accounts on this device is on a different passphrase, so '
          'nothing was changed.',
    _ => 'Could not change how the stores are encrypted: $error',
  };
}

final deviceEncryptionProvider =
    NotifierProvider<DeviceEncryptionController, DeviceEncryptionState>(
      DeviceEncryptionController.new,
    );

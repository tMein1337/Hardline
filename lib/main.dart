// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'bootstrap/matrix_bootstrap.dart';
import 'bootstrap/vodozemac_bootstrap.dart';
import 'core/app_info.dart';
import 'core/providers/injected_providers.dart';
import 'core/storage/store_cipher.dart';
import 'features/accounts/account_registry.dart';
import 'features/accounts/active_client.dart';
import 'features/auth/unlock_screen.dart';
import 'features/settings/device_encryption.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Puts this project's own licence into the same registry Flutter fills with
  // every package's, so `showLicensePage` under Settings -> About lists
  // Hardline itself alongside what it is built from rather than quietly
  // omitting the one licence that governs the whole work.
  LicenseRegistry.addLicense(_ownLicense);

  // Loaded before runApp so the theme and the account list can be read
  // synchronously and the first frame is already correctly colored, on the
  // right account.
  final prefs = await SharedPreferences.getInstance();

  // Must precede client construction: the SDK only builds its encryption layer
  // if vodozemac is initialised at that point. Failure is non-fatal.
  final encryptionAvailable = await initEncryption();
  debugPrint(
    encryptionAvailable
        ? 'End-to-end encryption is available.'
        : 'End-to-end encryption is NOT available.',
  );

  // Which account was last in use decides which database to open. Everything
  // after this point goes through ActiveClientController.
  var storageKey = bootStorageKey(readAccounts(prefs));

  // Whether this device's data is encrypted is asked of the store itself, not
  // of a setting: an encrypted SQLite file does not begin with the words
  // "SQLite format 3", and a file cannot be wrong about what it is. A
  // preference could, in either direction, and both directions are bad.
  //
  // When it is locked, the launch stops here and a lock screen runs in place of
  // the app until the passphrase opens the store — see `unlock_screen.dart`.
  String? passphrase;
  if (await storeIsEncrypted(await accountStorePath(storageKey))) {
    final outcome = await runUnlockGate(prefs: prefs, storageKey: storageKey);
    passphrase = outcome.passphrase;
    // Erasing deletes the stores *and* the account list, so which account to
    // open has to be asked again. It now answers "the default one", which does
    // not exist yet, and the launch continues as a first run.
    if (outcome.erased) storageKey = bootStorageKey(readAccounts(prefs));
  }

  final client = await buildMatrixClient(
    encryptionAvailable: encryptionAvailable,
    storageKey: storageKey,
    storePassphrase: passphrase,
  );

  runApp(
    hardlineRoot(
      prefs: prefs,
      boot: ActiveClient(client: client, storageKey: storageKey),
      encryptionAvailable: encryptionAvailable,
      passphrase: passphrase,
    ),
  );
}

/// The app's root, with everything `main()` had to settle before `runApp`.
///
/// A named builder rather than an inline tree so that a test can pump it
/// straight after the lock screen's root and prove the two can follow one
/// another — see `test/auth/launch_sequence_test.dart` and [kAppScopeKey].
@visibleForTesting
Widget hardlineRoot({
  required SharedPreferences prefs,
  required ActiveClient boot,
  required bool encryptionAvailable,
  required String? passphrase,
  Widget child = const HardlineApp(),
}) => ProviderScope(
  key: kAppScopeKey,
  overrides: [
    bootClientProvider.overrideWithValue(boot),
    prefsProvider.overrideWithValue(prefs),
    encryptionAvailableProvider.overrideWithValue(encryptionAvailable),
    bootPassphraseProvider.overrideWithValue(passphrase),
  ],
  child: child,
);

/// Reads the bundled `LICENSE` asset for the license registry.
///
/// Lazy, and a generator, because `LicenseRegistry` only drains it when
/// somebody actually opens the licence page — there is no reason for a launch
/// to pay for reading 34KB nobody has asked to see.
Stream<LicenseEntry> _ownLicense() async* {
  final text = await rootBundle.loadString('LICENSE');
  yield LicenseEntryWithLineBreaks(const [kAppName], text);
}

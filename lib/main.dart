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
import 'features/accounts/account_registry.dart';
import 'features/accounts/active_client.dart';

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
  final storageKey = bootStorageKey(readAccounts(prefs));
  final client = await buildMatrixClient(
    encryptionAvailable: encryptionAvailable,
    storageKey: storageKey,
  );

  runApp(
    ProviderScope(
      overrides: [
        bootClientProvider.overrideWithValue(
          ActiveClient(client: client, storageKey: storageKey),
        ),
        prefsProvider.overrideWithValue(prefs),
        encryptionAvailableProvider.overrideWithValue(encryptionAvailable),
      ],
      child: const HardlineApp(),
    ),
  );
}

/// Reads the bundled `LICENSE` asset for the license registry.
///
/// Lazy, and a generator, because `LicenseRegistry` only drains it when
/// somebody actually opens the licence page — there is no reason for a launch
/// to pay for reading 34KB nobody has asked to see.
Stream<LicenseEntry> _ownLicense() async* {
  final text = await rootBundle.loadString('LICENSE');
  yield LicenseEntryWithLineBreaks(const [kAppName], text);
}

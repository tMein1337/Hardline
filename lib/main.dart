import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'bootstrap/matrix_bootstrap.dart';
import 'bootstrap/vodozemac_bootstrap.dart';
import 'core/providers/injected_providers.dart';
import 'features/accounts/account_registry.dart';
import 'features/accounts/active_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      child: const MatrixClientApp(),
    ),
  );
}

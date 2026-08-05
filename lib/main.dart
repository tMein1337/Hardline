import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'bootstrap/matrix_bootstrap.dart';
import 'bootstrap/vodozemac_bootstrap.dart';
import 'core/providers/injected_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loaded before runApp so the theme can be read synchronously and the first
  // frame is already correctly colored.
  final prefs = await SharedPreferences.getInstance();

  // Must precede client construction: the SDK only builds its encryption layer
  // if vodozemac is initialised at that point. Failure is non-fatal.
  final encryptionAvailable = await initEncryption();
  debugPrint(
    encryptionAvailable
        ? 'End-to-end encryption is available.'
        : 'End-to-end encryption is NOT available.',
  );

  final client = await buildMatrixClient(
    encryptionAvailable: encryptionAvailable,
  );

  runApp(
    ProviderScope(
      overrides: [
        clientProvider.overrideWithValue(client),
        prefsProvider.overrideWithValue(prefs),
        encryptionAvailableProvider.overrideWithValue(encryptionAvailable),
      ],
      child: const MatrixClientApp(),
    ),
  );
}

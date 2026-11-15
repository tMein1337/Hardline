// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

/// Initialises the vodozemac (Olm/Megolm) native library used for E2EE.
///
/// Must be called before constructing the `Client`: the SDK only builds its
/// encryption layer if `vod.isInitialized()` is true at construction time.
///
/// Failure is deliberately non-fatal. If the native library is missing — a
/// build without the Rust toolchain, or a platform we have not compiled for —
/// the client still runs, `client.encryption` stays null, and unencrypted rooms
/// work normally. Encrypted rooms show placeholder text instead of crashing the
/// app on launch.
///
/// Returns whether encryption is available.
///
/// Safe to call more than once in a process, and answers every call with the
/// first one's result. The native bridge refuses a second initialisation
/// outright ("Should not initialize flutter_rust_bridge twice"), and that used
/// to be reported here as encryption being *unavailable* — so anything that
/// ran `main()` after something else had already loaded the library came up
/// unable to read an encrypted room, with a log line blaming the toolchain.
Future<bool> initEncryption() => _initialised ??= _load();

Future<bool>? _initialised;

Future<bool> _load() async {
  try {
    await vod.init();
    return true;
  } catch (error, stack) {
    debugPrint(
      'vodozemac failed to initialise; continuing without end-to-end '
      'encryption. Encrypted rooms will not be readable.\n$error\n$stack',
    );
    return false;
  }
}

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
Future<bool> initEncryption() async {
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

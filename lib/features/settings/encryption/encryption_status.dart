// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/injected_providers.dart';
import '../../../core/providers/matrix_tick_provider.dart';

/// What this session can prove about itself, cryptographically.
///
/// The distinction that matters, and the one that is easy to get wrong: a
/// session being verified *in our own store* and a session being trusted *by
/// other clients* are unrelated facts. Element decides the second one purely
/// from cross-signing signatures published to the homeserver. Marking a device
/// verified locally publishes nothing, so it changes nothing anyone else sees.
///
/// [ownDeviceSigned] is therefore the field that answers "why does Element show
/// a warning next to my messages".
@immutable
class EncryptionStatus {
  const EncryptionStatus({
    required this.available,
    required this.crossSigningEnabled,
    required this.secretsCached,
    required this.ownDeviceSigned,
    required this.keyBackupEnabled,
    required this.hasRecoveryKey,
  });

  /// vodozemac failed to load; nothing here is possible.
  const EncryptionStatus.unavailable()
    : available = false,
      crossSigningEnabled = false,
      secretsCached = false,
      ownDeviceSigned = false,
      keyBackupEnabled = false,
      hasRecoveryKey = false;

  final bool available;

  /// The account has cross-signing keys. False on an account that has never
  /// set encryption up in any client.
  final bool crossSigningEnabled;

  /// This session holds the cross-signing private keys, so it can sign other
  /// devices itself.
  final bool secretsCached;

  /// This device's key is signed by the account's self-signing key — the one
  /// thing other clients actually check.
  final bool ownDeviceSigned;

  final bool keyBackupEnabled;

  /// Secret storage has a default key, i.e. a recovery key exists.
  final bool hasRecoveryKey;

  /// Nothing to set up and nothing to unlock.
  bool get isComplete =>
      available && crossSigningEnabled && ownDeviceSigned && secretsCached;

  /// The account has no cross-signing at all, so there is nothing to unlock
  /// with a recovery key — it has to be created first.
  bool get needsSetup => available && !crossSigningEnabled;

  /// Cross-signing exists but this session is not part of it.
  bool get needsUnlock =>
      available && crossSigningEnabled && (!ownDeviceSigned || !secretsCached);
}

/// Recomputed on the sync tick: cross-signing state arrives as account data and
/// to-device messages, so it changes without anything on screen being touched.
///
/// An **async** provider watching the tick, which is the exception rather than
/// the rule — `isCached()` genuinely awaits. Everything else that watches the
/// tick is a synchronous `Provider` for a reason: a tick arrives every few
/// hundred milliseconds, so an async provider is thrown back to `AsyncLoading`
/// that often, and any `when(loading:)` rendering it becomes a permanent
/// spinner. Read this with `skipLoadingOnReload: true`, as the sessions pane
/// does, or do not read it at all.
final encryptionStatusProvider = FutureProvider<EncryptionStatus>((ref) async {
  final client = ref.watch(clientProvider);
  ref.watch(matrixTickProvider);

  final encryption = client.encryption;
  if (encryption == null) return const EncryptionStatus.unavailable();

  return EncryptionStatus(
    available: true,
    crossSigningEnabled: encryption.crossSigning.enabled,
    secretsCached: await encryption.crossSigning.isCached(),
    // `isUnknownSession` is literally "our own device key is not signed", which
    // is the same question read from the other direction.
    ownDeviceSigned: !client.isUnknownSession,
    keyBackupEnabled: encryption.keyManager.enabled,
    hasRecoveryKey: encryption.ssss.defaultKeyId != null,
  );
});

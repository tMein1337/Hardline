// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Asks the user for something the flow cannot proceed without.
///
/// Null means they declined, which is always a clean abort rather than an
/// error — nothing has been published at the points these are called.
typedef AskSecret = Future<String?> Function();

/// Creates or joins the account's cross-signing identity.
///
/// This is what makes the client standalone. Without it, verification marks
/// devices verified in our own store and publishes nothing, so Element keeps
/// showing "encrypted by a device not verified by its owner" against every
/// message we send — correctly, because no signature exists.
///
/// Two entirely different jobs live here, and which one applies depends on
/// whether the *account* has cross-signing at all:
///
///  * [createRecovery] — the account has none. Generate a recovery key, create
///    the three cross-signing keys, publish them, sign this device, and set up
///    the key backup. This is the fresh-account path.
///  * [signInWithRecoveryKey] — the account has cross-signing (set up here
///    before, or in Element). Unlock the existing secrets and sign this device
///    with them.
class EncryptionSetup {
  EncryptionSetup({
    required this.client,
    required this.askPassword,
    required this.askRecoveryKey,
  });

  final Client client;

  /// The homeserver requires re-authentication before it will accept new
  /// cross-signing keys.
  final AskSecret askPassword;

  /// Only called on the awkward paths where secret storage already exists and
  /// has to be opened before it can be reused.
  final AskSecret askRecoveryKey;

  Encryption get _encryption {
    final encryption = client.encryption;
    if (encryption == null) {
      throw const EncryptionSetupException(
        'Encryption is unavailable in this build.',
      );
    }
    return encryption;
  }

  /// Sets everything up from scratch and returns the new recovery key.
  ///
  /// The returned key is the only copy: it is derived from a private key that
  /// exists in memory here and nowhere else afterwards. Show it once, and say
  /// so.
  Future<String> createRecovery() {
    final encryption = _encryption;
    final completer = Completer<String>();
    // A cancelled stage fails the upload, which `Bootstrap` catches and turns
    // into its error state — so this needs no hand in completing the future.
    final uia = _handleUia();

    // The SDK calls `onUpdate` again from inside the very calls this makes, so
    // each state is acted on once — the same re-entrancy the verification
    // session guards against.
    BootstrapState? handled;

    void run(Future<void> Function() step) {
      unawaited(
        Future(step).catchError((Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        }),
      );
    }

    void drive(Bootstrap bootstrap) {
      if (completer.isCompleted || handled == bootstrap.state) return;
      handled = bootstrap.state;

      switch (bootstrap.state) {
        case BootstrapState.loading:
          break;

        // Never destroy secret storage that is already there. It may hold a
        // message-key backup belonging to sessions we know nothing about, and
        // wiping it is not recoverable.
        case BootstrapState.askWipeSsss:
          bootstrap.wipeSsss(false);

        case BootstrapState.askUseExistingSsss:
          bootstrap.useExistingSsss(true);

        case BootstrapState.openExistingSsss:
          run(() async {
            final key = await askRecoveryKey();
            if (key == null) throw const EncryptionSetupCancelled();
            await bootstrap.newSsssKey!.unlock(keyOrPassphrase: key.trim());
            await bootstrap.openExistingSsss();
          });

        case BootstrapState.askUnlockSsss:
          run(() async {
            final key = await askRecoveryKey();
            if (key == null) throw const EncryptionSetupCancelled();
            final oldKeys =
                bootstrap.oldSsssKeys?.values ?? const <OpenSSSS>[];
            for (final old in oldKeys) {
              await old.unlock(keyOrPassphrase: key.trim());
            }
            bootstrap.unlockedSsss();
          });

        // Secrets exist that no key on the account can decrypt. Continuing
        // means losing them, and that is not a decision to take on someone's
        // behalf inside a setup wizard.
        case BootstrapState.askBadSsss:
          run(
            () async => throw const EncryptionSetupException(
              'Secret storage on this account is in a state this app will not '
              'silently overwrite. Reset it from Element first.',
            ),
          );

        case BootstrapState.askNewSsss:
          // No passphrase: a recovery key is a full-strength random secret,
          // whereas a passphrase is whatever the user thought of, protecting
          // exactly the same thing.
          run(() => bootstrap.newSsss());

        case BootstrapState.askWipeCrossSigning:
          run(() => bootstrap.wipeCrossSigning(false));

        case BootstrapState.askSetupCrossSigning:
          run(
            () => bootstrap.askSetupCrossSigning(
              setupMasterKey: true,
              setupSelfSigningKey: true,
              setupUserSigningKey: true,
            ),
          );

        case BootstrapState.askWipeOnlineKeyBackup:
          bootstrap.wipeOnlineKeyBackup(false);

        // Worth doing in the same breath: without a backup, message history is
        // only as durable as the devices holding the keys.
        case BootstrapState.askSetupOnlineKeyBackup:
          run(() => bootstrap.askSetupOnlineKeyBackup(true));

        case BootstrapState.done:
          final key = bootstrap.newSsssKey?.recoveryKey;
          if (key == null) {
            completer.completeError(
              const EncryptionSetupException(
                'Setup finished without producing a recovery key.',
              ),
            );
          } else {
            completer.complete(key);
          }

        case BootstrapState.error:
          completer.completeError(
            EncryptionSetupException(
              bootstrap.errorResult?.error.toString() ??
                  'Setting up encryption failed.',
            ),
          );
      }
    }

    encryption.bootstrap(onUpdate: drive);
    return completer.future.whenComplete(uia.cancel);
  }

  /// Joins this session to cross-signing that already exists.
  ///
  /// `selfSign` unlocks secret storage, caches the cross-signing private keys,
  /// marks the master key verified and signs **this device** with the
  /// self-signing key. That last signature is the one other clients read.
  Future<void> signInWithRecoveryKey(String recoveryKey) async {
    final key = recoveryKey.trim();
    if (key.isEmpty) {
      throw const EncryptionSetupException('Enter your recovery key.');
    }

    try {
      await _encryption.crossSigning.selfSign(keyOrPassphrase: key);
    } on InvalidPassphraseException {
      throw const EncryptionSetupException(
        'That recovery key was not accepted. Check for a missing character — '
        'the spaces do not matter.',
      );
    }
  }

  /// Answers the re-authentication the homeserver demands before it accepts
  /// new cross-signing keys.
  ///
  /// Uploading them goes through `uiaRequestBackground`, which publishes to
  /// `client.onUiaRequest` and then *waits*. Without a listener the bootstrap
  /// simply hangs, with nothing on screen to say why.
  StreamSubscription<UiaRequest> _handleUia() {
    return client.onUiaRequest.stream.listen((uia) async {
      if (uia.state != UiaRequestState.waitForUser) return;

      if (!uia.nextStages.contains(AuthenticationTypes.password)) {
        uia.cancel(
          const EncryptionSetupException(
            'This homeserver wants a kind of confirmation this app cannot show '
            'yet. Set encryption up in Element instead.',
          ),
        );
        return;
      }

      final password = await askPassword();
      final userId = client.userID;
      if (password == null || userId == null) {
        uia.cancel(const EncryptionSetupCancelled());
        return;
      }

      await uia.completeStage(
        AuthenticationPassword(
          session: uia.session,
          password: password,
          identifier: AuthenticationUserIdentifier(user: userId),
        ),
      );
    });
  }
}

/// A failure with a message worth putting in front of someone.
@immutable
class EncryptionSetupException implements Exception {
  const EncryptionSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The user backed out. Not an error, and not worth reporting as one.
@immutable
class EncryptionSetupCancelled implements Exception {
  const EncryptionSetupCancelled();

  @override
  String toString() => 'Cancelled';
}

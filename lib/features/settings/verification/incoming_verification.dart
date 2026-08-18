// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/encryption.dart';

import '../../../core/providers/injected_providers.dart';
import 'verification_dialog.dart';
import 'verification_session.dart';

/// Verification requests started by somebody else.
///
/// The SDK only publishes these when `Client.verificationMethods` is non-empty;
/// it discards every `m.key.verification.*` event otherwise, silently. See the
/// constructor in `matrix_bootstrap.dart`.
final incomingVerificationProvider = StreamProvider<KeyVerification>((ref) {
  return ref.watch(clientProvider).onKeyVerificationRequest.stream;
});

/// Raises the verification dialog wherever the user happens to be.
///
/// Mounted in the shell rather than in the settings screen on purpose: a
/// request arrives when the *other* device starts it, and requiring the user to
/// have the right pane already open would mean most requests are never seen.
class IncomingVerificationListener extends ConsumerStatefulWidget {
  const IncomingVerificationListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<IncomingVerificationListener> createState() =>
      _IncomingVerificationListenerState();
}

class _IncomingVerificationListenerState
    extends ConsumerState<IncomingVerificationListener> {
  /// One at a time. A second dialog stacked on the first would hide which
  /// request the digits on screen belong to, and that is the one thing the user
  /// has to be certain of.
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(incomingVerificationProvider, (_, next) {
      final request = next.value;
      if (request == null || _showing) return;
      _show(request);
    });

    return widget.child;
  }

  Future<void> _show(KeyVerification request) async {
    _showing = true;
    try {
      await VerificationDialog.show(context, VerificationSession(request));
    } finally {
      _showing = false;
    }
  }
}

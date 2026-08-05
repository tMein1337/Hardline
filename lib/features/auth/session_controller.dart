import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';

/// Whether a sign-out is in flight.
class SessionController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Signs out and clears the local store.
  ///
  /// The router flips back to the login screen on its own, driven by the
  /// login-state stream, so there is nothing to navigate here.
  Future<void> signOut() async {
    if (state) return;
    state = true;
    try {
      await ref.read(clientProvider).logout();
    } catch (error) {
      // logout() clears local state in a finally block even when the server
      // call fails, so the session is gone either way.
      debugPrint('Logout request failed, session cleared locally: $error');
    } finally {
      state = false;
    }
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, bool>(
  SessionController.new,
);

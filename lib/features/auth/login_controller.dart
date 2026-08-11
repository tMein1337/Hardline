import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import 'login_form_state.dart';

/// Shown to the homeserver in the user's device list.
const _deviceDisplayName = 'Matrix Client (Windows)';

/// Turns what the user typed into a homeserver URL.
///
/// Accepts `matrix.org`, `https://matrix.org` and `https://matrix.org/` alike;
/// bare hosts are assumed to be https.
Uri normalizeHomeserver(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    throw const FormatException('Enter a homeserver, for example matrix.org');
  }

  final withScheme = text.contains('://') ? text : 'https://$text';
  final uri = Uri.parse(withScheme);

  if (uri.host.isEmpty) {
    throw FormatException('"$input" is not a valid homeserver address');
  }
  return uri;
}

/// Converts SDK and transport exceptions into something worth showing a user.
String describeAuthError(Object error) {
  if (error is MatrixException) {
    switch (error.errcode) {
      case 'M_FORBIDDEN':
        return 'Incorrect username or password.';
      case 'M_USER_DEACTIVATED':
        return 'This account has been deactivated.';
      case 'M_LIMIT_EXCEEDED':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'M_UNKNOWN_TOKEN':
        return 'This session has expired. Please sign in again.';
      default:
        return error.errorMessage;
    }
  }
  if (error is FormatException) {
    return error.message;
  }
  if (error is SocketException || error is HandshakeException) {
    return "Couldn't reach that homeserver. Check the address and your "
        'internet connection.';
  }
  if (error is TimeoutException) {
    return 'The homeserver took too long to respond.';
  }
  // checkHomeserver throws these when the server is not usable.
  return error.toString();
}

class LoginController extends Notifier<LoginFormState> {
  @override
  LoginFormState build() => const LoginFormState();

  /// Signs in with a password.
  ///
  /// On success nothing is set here: `login()` calls `Client.init()` internally,
  /// which emits `LoginState.loggedIn`, and the router swaps the screen out from
  /// under this form.
  ///
  /// [target] is the client to authenticate. It is not the live one when an
  /// account is being *added*: that login has to land in a database of its own,
  /// which exists before the account does. Returns whether it worked, because
  /// the add-account caller has follow-up work and cannot infer success from a
  /// router that has not moved.
  Future<bool> signIn({
    required String homeserver,
    required String username,
    required String password,
    Client? target,
  }) async {
    if (state.busy) return false;
    state = const LoginFormState(busy: true);

    try {
      final Client client = target ?? ref.read(clientProvider);

      // Resolves .well-known, checks supported versions and login flows.
      await client.checkHomeserver(normalizeHomeserver(homeserver));

      await client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username.trim()),
        password: password,
        initialDeviceDisplayName: _deviceDisplayName,
      );

      state = const LoginFormState();
      return true;
    } catch (error) {
      state = LoginFormState(error: describeAuthError(error));
      return false;
    }
  }

  void dismissError() => state = state.copyWith(clearError: true);
}

final loginControllerProvider =
    NotifierProvider<LoginController, LoginFormState>(LoginController.new);

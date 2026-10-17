// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../core/providers/injected_providers.dart';
import 'login_controller.dart';
import 'registration_flow.dart';

/// What the registration screen is doing.
@immutable
class RegistrationState {
  const RegistrationState({
    this.busy = false,
    this.error,
    this.terms,
    this.needsToken = false,
    this.browserUrl,
  });

  final bool busy;

  /// A failure worth showing. Already translated out of the SDK's exception.
  final String? error;

  /// Where the homeserver's terms live, when it wants them accepted.
  ///
  /// Non-null puts the screen into its accept-the-terms step. There is nothing
  /// to render inline: a policy document is a web page, and the honest thing
  /// is a link plus a checkbox rather than a paraphrase.
  final Uri? terms;

  /// Whether the homeserver wants a registration token.
  final bool needsToken;

  /// Where to finish, when this app cannot.
  ///
  /// Set alongside [error] when the flow needs a captcha, an email or a phone
  /// number. The screen turns it into a button rather than leaving somebody
  /// with a refusal and nowhere to go.
  final Uri? browserUrl;

  RegistrationState copyWith({
    bool? busy,
    String? error,
    Uri? terms,
    bool? needsToken,
    Uri? browserUrl,
    bool clearError = false,
    bool clearTerms = false,
  }) => RegistrationState(
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    terms: clearTerms ? null : (terms ?? this.terms),
    needsToken: needsToken ?? this.needsToken,
    browserUrl: clearError ? null : (browserUrl ?? this.browserUrl),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegistrationState &&
          busy == other.busy &&
          error == other.error &&
          terms == other.terms &&
          needsToken == other.needsToken &&
          browserUrl == other.browserUrl;

  @override
  int get hashCode => Object.hash(busy, error, terms, needsToken, browserUrl);
}

/// Creates an account, walking the homeserver's UIA stages.
///
/// Registration is a loop, not a request: the first `POST /register` is
/// *expected* to fail with 401 and a list of flows, and every subsequent call
/// replays the same username and password with one more stage answered. The
/// session id ties them together.
///
/// Stages this client cannot show are not attempted — see
/// [kSupportedRegistrationStages]. The screen offers the homeserver's own
/// registration page instead, which is a real way through rather than a dead
/// end.
class RegistrationController extends Notifier<RegistrationState> {
  @override
  RegistrationState build() => const RegistrationState();

  /// The session the homeserver gave us, carried across stages.
  String? _session;

  /// Held so a stage can be answered without asking for them again.
  String _homeserver = '';
  String _username = '';
  String _password = '';

  void reset() {
    _session = null;
    state = const RegistrationState();
  }

  /// Begins registration. Returns true once the account exists and is signed in.
  Future<bool> start({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    if (state.busy) return false;

    _homeserver = homeserver;
    _username = username.trim();
    _password = password;
    _session = null;

    state = const RegistrationState(busy: true);
    return _attempt(null);
  }

  /// Answers the terms stage.
  Future<bool> acceptTerms() {
    state = state.copyWith(busy: true, clearError: true, clearTerms: true);
    return _attempt(
      AuthenticationData(type: 'm.login.terms', session: _session),
    );
  }

  /// Answers the registration-token stage.
  Future<bool> submitToken(String token) {
    state = state.copyWith(busy: true, clearError: true);
    return _attempt(
      AuthenticationData(
        type: 'm.login.registration_token',
        session: _session,
        additionalFields: {'token': token.trim()},
      ),
    );
  }

  /// One round trip, and whatever the answer implies.
  Future<bool> _attempt(AuthenticationData? auth) async {
    try {
      final client = ref.read(clientProvider);
      await client.checkHomeserver(normalizeHomeserver(_homeserver));

      await client.register(
        username: _username,
        password: _password,
        auth: auth,
        initialDeviceDisplayName: 'Hardline (Windows)',
      );

      // Registering signs the account in — `Client.init()` runs inside the SDK
      // and the router swaps the screen out from under this form, exactly as
      // it does after a login.
      state = const RegistrationState();
      return true;
    } on MatrixException catch (error) {
      if (!error.requireAdditionalAuthentication) {
        state = RegistrationState(error: _describe(error));
        return false;
      }
      return _handleStages(error);
    } catch (error) {
      state = RegistrationState(error: describeAuthError(error));
      return false;
    }
  }

  /// Decides what to ask for next, given the server's 401.
  Future<bool> _handleStages(MatrixException error) async {
    _session = error.session ?? _session;

    final flows = error.authenticationFlows ?? const <AuthenticationFlow>[];
    final blocked = registrationBlockedReason(flows);
    if (blocked != null) {
      state = RegistrationState(
        error: blocked,
        browserUrl: registrationPageFor(normalizeHomeserver(_homeserver)),
      );
      return false;
    }

    final flow = chooseRegistrationFlow(flows)!;
    final next = nextRegistrationStage(
      flow,
      error.completedAuthenticationFlows,
    );

    switch (next) {
      case null:
        // Every stage is done and the server still said 401. Retrying would
        // loop, so this stops and says so rather than spinning.
        state = const RegistrationState(
          error:
              'The homeserver did not accept the registration even though '
              'every step was completed. Try its own registration page.',
        );
        return false;

      case AuthenticationTypes.dummy:
        // Nothing to ask. Answered immediately rather than shown, which is the
        // entire purpose of the dummy stage.
        return _attempt(
          AuthenticationData(
            type: AuthenticationTypes.dummy,
            session: _session,
          ),
        );

      case AuthenticationTypes.password:
        // The password is already in hand; this stage is the server asking us
        // to confirm the one we sent.
        return _attempt(
          AuthenticationData(
            type: AuthenticationTypes.password,
            session: _session,
            additionalFields: {
              'password': _password,
              'identifier': {'type': 'm.id.user', 'user': _username},
            },
          ),
        );

      case 'm.login.terms':
        state = RegistrationState(terms: _termsUrl(error));
        return false;

      case 'm.login.registration_token':
        state = const RegistrationState(needsToken: true);
        return false;

      default:
        state = RegistrationState(
          error:
              'This homeserver asked for "$next", which this app cannot '
              'show.',
          browserUrl: registrationPageFor(normalizeHomeserver(_homeserver)),
        );
        return false;
    }
  }

  /// The policy document to link to.
  ///
  /// The params carry one entry per policy, each with a version and a set of
  /// languages. English is preferred and the first of anything is the
  /// fallback: a link to a document in the wrong language is more use than no
  /// link at all.
  Uri? _termsUrl(MatrixException error) {
    final policies = error.authenticationParams?['m.login.terms'];
    if (policies is! Map) return null;

    for (final policy in policies.values) {
      if (policy is! Map) continue;
      final languages = [
        for (final entry in policy.entries)
          if (entry.value is Map && (entry.value as Map)['url'] is String)
            (
              code: entry.key.toString(),
              url: (entry.value as Map)['url'] as String,
            ),
      ];
      if (languages.isEmpty) continue;

      final english = languages.where((l) => l.code.startsWith('en'));
      final chosen = english.isNotEmpty ? english.first : languages.first;
      return Uri.tryParse(chosen.url);
    }
    return null;
  }

  String _describe(MatrixException error) => switch (error.errcode) {
    'M_USER_IN_USE' => 'That username is taken on this homeserver.',
    'M_INVALID_USERNAME' => 'This homeserver will not accept that username.',
    'M_EXCLUSIVE' =>
      'That username is reserved on this homeserver. Pick another.',
    'M_FORBIDDEN' =>
      'This homeserver is not accepting new accounts, or the registration '
          'token was wrong.',
    'M_WEAK_PASSWORD' =>
      'This homeserver considers that password too weak. ${error.errorMessage}',
    _ => error.errorMessage,
  };
}

final registrationControllerProvider =
    NotifierProvider<RegistrationController, RegistrationState>(
      RegistrationController.new,
    );

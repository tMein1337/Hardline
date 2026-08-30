// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// The user-interactive-auth stages this client can drive itself.
///
/// Everything else is handed to a browser. That is not laziness: `m.login.sso`
/// and `m.login.recaptcha` both mean "show the user somebody else's web page
/// and let them interact with it", which needs a webview — a dependency this
/// app does not have and would not want for one screen. `m.login.email.identity`
/// needs the client to poll while the user reads their mail, and to hold the
/// registration open across an application restart.
///
/// Handing those to the homeserver's own registration page is the honest
/// answer: the user finishes there, comes back, and signs in normally.
const Set<String> kSupportedRegistrationStages = {
  AuthenticationTypes.dummy,
  AuthenticationTypes.password,
  'm.login.terms',
  'm.login.registration_token',
};

/// Which flow to attempt, or null when the server offers none we can complete.
///
/// A homeserver offers several flows and the client picks one. Chosen by
/// **fewest stages among the ones we fully support**, because every stage is
/// something to put in front of somebody and the shortest complete path is the
/// kindest one.
///
/// A flow is only a candidate if *every* stage in it is supported. A flow that
/// is three-quarters doable is not doable: getting to the last stage and
/// discovering it needs a captcha wastes the account name and the password
/// somebody just chose.
AuthenticationFlow? chooseRegistrationFlow(List<AuthenticationFlow> flows) {
  AuthenticationFlow? best;
  for (final flow in flows) {
    if (!flow.stages.every(kSupportedRegistrationStages.contains)) continue;
    if (best == null || flow.stages.length < best.stages.length) best = flow;
  }
  return best;
}

/// The next stage of [flow] that has not been completed yet.
///
/// [completed] is the server's own list, which is what makes this reliable:
/// the client does not track its own progress, it asks each time. A stage the
/// server considers done is skipped even if we never consciously did it —
/// which is exactly what happens with `m.login.dummy` on some servers.
String? nextRegistrationStage(
  AuthenticationFlow flow,
  List<String> completed,
) {
  for (final stage in flow.stages) {
    if (!completed.contains(stage)) return stage;
  }
  return null;
}

/// Why registration cannot be completed here, in words worth showing.
///
/// Null when [flows] contains something workable. Deliberately names the
/// obstacle rather than saying "unsupported": somebody who is told a captcha
/// is in the way understands the browser button beneath it, and somebody told
/// "registration failed" does not.
String? registrationBlockedReason(List<AuthenticationFlow> flows) {
  if (flows.isEmpty) {
    return 'This homeserver did not offer a way to register.';
  }
  if (chooseRegistrationFlow(flows) != null) return null;

  final stages = {for (final flow in flows) ...flow.stages}
    ..removeAll(kSupportedRegistrationStages);

  if (stages.contains(AuthenticationTypes.recaptcha)) {
    return 'This homeserver requires a captcha, which has to be solved in a '
        'browser. Open its registration page, make the account there, then '
        'come back and sign in.';
  }
  if (stages.contains(AuthenticationTypes.emailIdentity)) {
    return 'This homeserver requires email verification during registration, '
        'which this app cannot wait for. Open its registration page, make the '
        'account there, then come back and sign in.';
  }
  if (stages.contains(AuthenticationTypes.msisdn)) {
    return 'This homeserver requires a phone number during registration. Open '
        'its registration page, make the account there, then come back and '
        'sign in.';
  }
  return 'This homeserver asks for a kind of confirmation this app cannot '
      'show. Open its registration page, make the account there, then come '
      'back and sign in.';
}

/// Whether [username] is a plausible localpart.
///
/// Checked before the request so a typo costs no round trip, and deliberately
/// looser than the spec's grammar: homeservers vary in what they accept, so
/// this rejects only what is certainly wrong and lets the server rule on the
/// rest.
String? validateLocalpart(String username) {
  final trimmed = username.trim();
  if (trimmed.isEmpty) return 'Pick a username.';
  if (trimmed.startsWith('@')) {
    return 'Just the name, without the @ and without the server.';
  }
  if (trimmed.contains(':')) {
    return 'Just the name — the server comes from the homeserver field.';
  }
  if (trimmed.contains(RegExp(r'\s'))) {
    return 'A username cannot contain spaces.';
  }
  if (!RegExp(r'^[a-z0-9._=/+-]+$').hasMatch(trimmed)) {
    return 'Use lowercase letters, digits, and . _ = - / + only.';
  }
  return null;
}

/// Whether the two password fields agree and are worth sending.
String? validatePassword(String password, String confirmation) {
  if (password.isEmpty) return 'Pick a password.';
  // Deliberately low. The homeserver enforces its own policy and will say so;
  // inventing a stricter one here would reject a password the server would
  // have accepted, with no way for the user to know who objected.
  if (password.length < 8) {
    return 'Use at least 8 characters.';
  }
  if (password != confirmation) return 'The two passwords do not match.';
  return null;
}

/// The registration page a homeserver's own web client would serve.
///
/// A guess, and openly one: there is no discovery for this. Element's hosted
/// client at the homeserver's domain is the overwhelmingly common answer, and
/// a wrong guess costs a browser tab rather than anything worse.
Uri registrationPageFor(Uri homeserver) =>
    homeserver.replace(path: '/', fragment: '/register');

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../theme/theme_context.dart';
import 'text_prompt.dart';

/// Runs a request that the homeserver may want re-authentication for.
///
/// The user-interactive auth dance is: send the request, get a 401 carrying a
/// `session`, send it again with credentials attached. Only the password stage
/// is implemented — it is the only one signing a device out actually needs on a
/// password account, and guessing at SSO or reCAPTCHA stages we cannot render
/// would fail later and more confusingly than saying so here.
///
/// Returns true when the request went through.
Future<bool> runWithPasswordAuth(
  BuildContext context, {
  required Client client,
  required Future<void> Function(AuthenticationData? auth) request,
  required String purpose,
}) async {
  try {
    await request(null);
    return true;
  } on MatrixException catch (error) {
    if (!error.requireAdditionalAuthentication) rethrow;

    final flows = error.authenticationFlows ?? const <AuthenticationFlow>[];
    final passwordOnly = flows.any(
      (flow) =>
          flow.stages.length == 1 &&
          flow.stages.single == AuthenticationTypes.password,
    );
    if (!passwordOnly) {
      if (context.mounted) {
        await _explain(
          context,
          'This homeserver wants a kind of confirmation this app cannot show '
          'yet. Use Element for this one.',
        );
      }
      return false;
    }

    if (!context.mounted) return false;
    final password = await _askPassword(context, purpose: purpose);
    if (password == null) return false;

    final userId = client.userID;
    if (userId == null) return false;

    await request(
      AuthenticationPassword(
        session: error.session,
        password: password,
        identifier: AuthenticationUserIdentifier(user: userId),
      ),
    );
    return true;
  }
}

Future<String?> _askPassword(
  BuildContext context, {
  required String purpose,
}) async {
  final result = await promptForText(
    context,
    title: 'Confirm it is you',
    description: purpose,
    hint: 'Password',
    confirmLabel: 'Confirm',
    obscure: true,
  );
  return result == null || result.isEmpty ? null : result;
}

Future<void> _explain(BuildContext context, String message) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: context.colors.floatingSurface,
    content: Text(message, style: context.text.messageBody),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('OK', style: TextStyle(color: context.colors.textMuted)),
      ),
    ],
  ),
);

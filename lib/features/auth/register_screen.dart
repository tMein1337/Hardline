// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/open_link.dart';
import '../../theme/theme_context.dart';
import 'widgets/login_text_field.dart';
import 'registration_controller.dart';
import 'registration_flow.dart';

/// Makes a new account on a homeserver.
///
/// The app had none of this. The login screen offered a homeserver, a username
/// and a password and nothing else, so a new user's only route in was to
/// install Element, register there, and come back — which is a poor first
/// impression for a client that otherwise stands on its own.
///
/// Only the stages this app can honestly show are attempted; see
/// `registration_flow.dart` for which and why. Anything else ends in a button
/// to the homeserver's own registration page rather than a refusal.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const RegisterScreen()));

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _homeserver = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _token = TextEditingController();

  bool _termsAccepted = false;

  /// Set by the local checks, so a typo does not cost a round trip.
  String? _localError;

  @override
  void dispose() {
    _homeserver.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final problem =
        validateLocalpart(_username.text) ??
        validatePassword(_password.text, _confirm.text);
    if (problem != null) {
      setState(() => _localError = problem);
      return;
    }
    setState(() => _localError = null);

    final created = await ref
        .read(registrationControllerProvider.notifier)
        .start(
          homeserver: _homeserver.text,
          username: _username.text,
          password: _password.text,
        );

    // On success the router replaces everything below this route, but the
    // route itself is still on the stack — without this it stays on top of the
    // app somebody just signed into.
    if (created && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(registrationControllerProvider);

    return Scaffold(
      backgroundColor: colors.timelineBackground,
      appBar: AppBar(
        title: Text('Create an account', style: context.text.title),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'The homeserver is where the account lives, and it becomes '
                  'part of your address. It cannot be changed later.',
                  style: context.text.subtitle,
                ),
                const SizedBox(height: 20),
                LoginTextField(
                  controller: _homeserver,
                  label: 'Homeserver',
                  hintText: 'matrix.org',
                  enabled: !state.busy,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                LoginTextField(
                  controller: _username,
                  label: 'Username',
                  hintText: 'alice',
                  enabled: !state.busy,
                ),
                const SizedBox(height: 12),
                LoginTextField(
                  controller: _password,
                  label: 'Password',
                  obscureText: true,
                  enabled: !state.busy,
                ),
                const SizedBox(height: 12),
                LoginTextField(
                  controller: _confirm,
                  label: 'Password again',
                  obscureText: true,
                  enabled: !state.busy,
                  onSubmitted: (_) => _submit(),
                ),

                if (state.terms case final terms?) ...[
                  const SizedBox(height: 20),
                  _Terms(
                    url: terms,
                    accepted: _termsAccepted,
                    onChanged: (value) =>
                        setState(() => _termsAccepted = value),
                  ),
                ],

                if (state.needsToken) ...[
                  const SizedBox(height: 20),
                  Text(
                    'This homeserver needs an invitation token. Whoever runs '
                    'it issues them.',
                    style: context.text.subtitle,
                  ),
                  const SizedBox(height: 8),
                  LoginTextField(
                    controller: _token,
                    label: 'Registration token',
                    enabled: !state.busy,
                  ),
                ],

                if (_localError ?? state.error case final message?) ...[
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: context.text.subtitle.copyWith(color: colors.danger),
                  ),
                ],

                if (state.browserUrl case final url?) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => openExternalUrl(context, url),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open the registration page'),
                  ),
                ],

                const SizedBox(height: 24),
                FilledButton(
                  onPressed: state.busy ? null : _onPrimary,
                  child: state.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_primaryLabel(state)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _primaryLabel(RegistrationState state) {
    if (state.terms != null) return 'Accept and continue';
    if (state.needsToken) return 'Continue';
    return 'Create account';
  }

  /// One button, three meanings — because at any moment there is exactly one
  /// thing to do next, and a screen with three buttons two of which are
  /// disabled says less than a screen with one.
  Future<void> _onPrimary() async {
    final controller = ref.read(registrationControllerProvider.notifier);
    final state = ref.read(registrationControllerProvider);

    if (state.terms != null) {
      if (!_termsAccepted) {
        setState(() => _localError = 'Accept the terms to continue.');
        return;
      }
      setState(() => _localError = null);
      await controller.acceptTerms();
      return;
    }

    if (state.needsToken) {
      if (_token.text.trim().isEmpty) {
        setState(() => _localError = 'Enter the token.');
        return;
      }
      setState(() => _localError = null);
      await controller.submitToken(_token.text);
      return;
    }

    await _submit();
  }
}

class _Terms extends StatelessWidget {
  const _Terms({
    required this.url,
    required this.accepted,
    required this.onChanged,
  });

  final Uri url;
  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: accepted,
          onChanged: (value) => onChanged(value ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'I accept this homeserver\'s ',
                  style: context.text.subtitle,
                ),
                // A link rather than the text itself: a policy document is a
                // web page, and paraphrasing somebody's terms inside a
                // checkbox would be putting words in their mouth.
                TextButton(
                  onPressed: () => openExternalUrl(context, url),
                  child: const Text('terms and conditions'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

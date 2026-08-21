// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import '../../theme/theme_context.dart';
import '../accounts/account_actions.dart';
import '../accounts/active_client.dart';
import 'login_controller.dart';
import 'widgets/login_card.dart';
import 'widgets/login_text_field.dart';

/// Remembered so signing back in after a logout does not mean retyping the
/// server every time.
const _lastHomeserverKey = 'last_homeserver';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.pending});

  /// Set when this screen is adding a *second* account rather than signing in.
  ///
  /// The difference is which client the credentials go to: an added account
  /// authenticates into a database of its own, built before the login, so that
  /// the account being left keeps its session intact.
  final PendingLogin? pending;

  /// Pushes the add-account flow, tearing the throwaway session down again if
  /// the user backs out.
  static Future<void> addAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final actions = ref.read(accountActionsProvider.notifier);
    final pending = await actions.beginAddAccount();
    if (!context.mounted) {
      await actions.cancelAddAccount(pending);
      return;
    }

    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginScreen(pending: pending)),
    );
    if (added != true) await actions.cancelAddAccount(pending);
  }

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final TextEditingController _homeserver;
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _homeserver = TextEditingController(
      text: ref.read(prefsProvider).getString(_lastHomeserverKey) ?? '',
    );
  }

  @override
  void dispose() {
    _homeserver.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pending = widget.pending;
    final homeserver = _homeserver.text.trim();

    // Every provider this method needs is read *before* the first await, and
    // held rather than re-read afterwards, because this screen is normally gone
    // by the time the await returns.
    //
    // The SDK's `login()` calls `Client.init()` internally, and `init()` emits
    // `LoginState.loggedIn` and *then* waits for the first sync — a whole
    // network round trip later. The router acts on `loggedIn` at the next
    // frame, so `LoginScreen` has already been replaced by the shell while
    // `signIn` is still awaiting. A `ref` read at that point throws the
    // "widget is about to or has been unmounted" StateError, and nothing
    // awaits `_submit`, so it surfaces as an unhandled exception on the first
    // launch of a fresh install. All three of these are app-lifetime
    // providers, so a captured reference stays valid.
    final login = ref.read(loginControllerProvider.notifier);
    final prefs = ref.read(prefsProvider);
    final accounts = ref.read(accountActionsProvider.notifier);

    final ok = await login.signIn(
      homeserver: homeserver,
      username: _username.text,
      password: _password.text,
      target: pending?.client,
    );

    if (homeserver.isNotEmpty) {
      await prefs.setString(_lastHomeserverKey, homeserver);
    }

    // A first login moves the router on its own, driven by the login-state
    // stream. An *added* account does not: the live client has not changed
    // until we say so.
    if (!ok || pending == null) return;
    await accounts.completeAddAccount(pending);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(loginControllerProvider);
    final encryptionAvailable = ref.watch(encryptionAvailableProvider);
    final adding = widget.pending != null;

    return Scaffold(
      backgroundColor: colors.timelineBackground,
      body: LoginCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              adding ? 'Add an account' : 'Welcome back!',
              textAlign: TextAlign.center,
              style: context.text.title.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              adding
                  ? 'Signing in here does not sign you out of the account you '
                        'are using now.'
                  : "We're so excited to see you again",
              textAlign: TextAlign.center,
              style: context.text.subtitle,
            ),
            const SizedBox(height: 24),

            if (state.error != null) ...[
              _ErrorBanner(message: state.error!),
              const SizedBox(height: 16),
            ],

            LoginTextField(
              label: 'Homeserver',
              controller: _homeserver,
              hintText: 'matrix.org',
              autofocus: true,
              enabled: !state.busy,
            ),
            const SizedBox(height: 20),
            LoginTextField(
              label: 'Username',
              controller: _username,
              hintText: 'alice',
              enabled: !state.busy,
            ),
            const SizedBox(height: 20),
            LoginTextField(
              label: 'Password',
              controller: _password,
              obscureText: true,
              enabled: !state.busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: state.busy ? null : _submit,
              child: state.busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colors.textOnAccent,
                      ),
                    )
                  : const Text('Log In'),
            ),

            if (adding) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: state.busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: colors.textMuted),
                ),
              ),
            ],

            if (!encryptionAvailable) ...[
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_open, size: 16, color: colors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Encryption is unavailable in this build. Encrypted '
                      'rooms will not be readable.',
                      style: context.text.subtitle.copyWith(
                        color: colors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.metrics.rowRadius),
        border: Border.all(color: colors.danger.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: context.text.subtitle.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

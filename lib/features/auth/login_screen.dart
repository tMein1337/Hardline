import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/injected_providers.dart';
import '../../theme/theme_context.dart';
import 'login_controller.dart';
import 'widgets/login_card.dart';
import 'widgets/login_text_field.dart';

/// Remembered so signing back in after a logout does not mean retyping the
/// server every time.
const _lastHomeserverKey = 'last_homeserver';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

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
    final homeserver = _homeserver.text.trim();
    await ref
        .read(loginControllerProvider.notifier)
        .signIn(
          homeserver: homeserver,
          username: _username.text,
          password: _password.text,
        );

    if (homeserver.isNotEmpty) {
      await ref.read(prefsProvider).setString(_lastHomeserverKey, homeserver);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(loginControllerProvider);
    final encryptionAvailable = ref.watch(encryptionAvailableProvider);

    return Scaffold(
      backgroundColor: colors.chatBackground,
      body: LoginCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Welcome back!',
              textAlign: TextAlign.center,
              style: context.text.title.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              "We're so excited to see you again",
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

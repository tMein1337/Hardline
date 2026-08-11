import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/bootstrap_provider.dart';
import '../core/providers/login_state_provider.dart';
import '../features/accounts/account_actions.dart';
import '../features/accounts/account_sync.dart';
import '../features/auth/login_screen.dart';
import '../features/common/app_error_view.dart';
import '../features/common/app_splash.dart';
import '../features/shell/home_shell.dart';

/// Decides what the app shows: splash while the session is restored, then
/// either the login screen or the main shell.
class AppRouter extends ConsumerWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);
    final accounts = ref.watch(accountActionsProvider);
    // Records the live session in the account list. Self-guarding: it does
    // nothing until somebody is signed in.
    ref.watch(accountSyncProvider);

    // An account switch replaces the client under everything below, so the
    // shell is taken down for the duration rather than left to rebuild against
    // a client that is being disposed.
    if (accounts.busy) {
      return AppSplash(message: accounts.message ?? 'Switching account…');
    }

    if (accounts.error case final error?) {
      return AppErrorView(
        title: 'Could not switch account',
        error: error,
        onRetry: () =>
            ref.read(accountActionsProvider.notifier).dismissError(),
      );
    }

    return bootstrap.when(
      loading: () => const AppSplash(message: 'Restoring session…'),
      error: (error, _) => AppErrorView(
        title: 'Could not start',
        error: error,
        onRetry: () => ref.invalidate(bootstrapProvider),
      ),
      data: (_) => ref.watch(isLoggedInProvider)
          ? const HomeShell()
          : const LoginScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/bootstrap_provider.dart';
import '../core/providers/login_state_provider.dart';
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

    return bootstrap.when(
      loading: () => const AppSplash(message: 'Restoring session…'),
      error: (error, _) => AppErrorView(
        title: 'Could not start',
        error: error,
        onRetry: () => ref.invalidate(bootstrapProvider),
      ),
      data: (_) =>
          ref.watch(isLoggedInProvider) ? const HomeShell() : const LoginScreen(),
    );
  }
}

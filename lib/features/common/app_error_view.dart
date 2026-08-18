// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';

/// Full-screen failure state with a retry affordance.
///
/// Used for bootstrap failures (a corrupt or locked database, most likely),
/// where the alternative is a blank window with no explanation.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.error,
    this.title = 'Something went wrong',
    this.onRetry,
  });

  final Object error;
  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.timelineBackground,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: colors.danger, size: 40),
                const SizedBox(height: 16),
                Text(title, style: context.text.title),
                const SizedBox(height: 8),
                SelectableText(
                  error.toString(),
                  style: context.text.subtitle,
                  maxLines: 8,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: onRetry,
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

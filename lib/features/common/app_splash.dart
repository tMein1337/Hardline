import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';

/// Shown while the stored session is being restored.
///
/// Already themed, because preferences are loaded before `runApp` — there is no
/// flash of default colors before this appears.
class AppSplash extends StatelessWidget {
  const AppSplash({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.chatBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: colors.accent,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!, style: context.text.subtitle),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// Placeholder for the chat column when no room is selected.
class EmptyChatView extends StatelessWidget {
  const EmptyChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      color: colors.chatBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: colors.textFaint),
            const SizedBox(height: 16),
            Text('No room selected', style: context.text.title),
            const SizedBox(height: 4),
            Text(
              'Pick a room on the left to start reading.',
              style: context.text.subtitle,
            ),
          ],
        ),
      ),
    );
  }
}

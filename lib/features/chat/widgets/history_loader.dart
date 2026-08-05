import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// Spinner shown at the top of the list while older messages are fetched.
class HistoryLoader extends StatelessWidget {
  const HistoryLoader({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: context.colors.textMuted,
        ),
      ),
    ),
  );
}

/// The block at the very start of a room's history.
class ChannelWelcome extends StatelessWidget {
  const ChannelWelcome({super.key, required this.roomName});

  final String roomName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.metrics.contentPadding,
        32,
        context.metrics.contentPadding,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: colors.elevatedSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.tag, size: 40, color: colors.textHeader),
          ),
          const SizedBox(height: 12),
          Text(
            'Welcome to #$roomName',
            style: context.text.title.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 6),
          Text(
            'This is the beginning of this conversation.',
            style: context.text.subtitle,
          ),
        ],
      ),
    );
  }
}

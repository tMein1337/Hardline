import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/util/time_format.dart';
import '../../../theme/theme_context.dart';

const _localizations = MatrixDefaultLocalizations();

/// Muted one-liner for joins, leaves, topic changes and similar.
class SystemEventTile extends StatelessWidget {
  const SystemEventTile({super.key, required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;

    // The SDK phrases these ("Alice joined the chat"), including the actor.
    final text = event.calcLocalizedBodyFallback(
      _localizations,
      withSenderNamePrefix: false,
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.contentPadding,
        vertical: 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: metrics.avatarSize,
            child: Icon(
              _iconFor(event.type),
              size: 16,
              color: colors.textFaint,
            ),
          ),
          SizedBox(width: metrics.avatarGutter),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: text, style: context.text.systemEvent),
                  const TextSpan(text: '  '),
                  TextSpan(
                    text: formatClockTime(event.originServerTs.toLocal()),
                    style: context.text.timestamp.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
    EventTypes.RoomMember => Icons.person_add_alt,
    EventTypes.RoomName || EventTypes.RoomAvatar => Icons.edit_outlined,
    EventTypes.RoomTopic => Icons.subject,
    EventTypes.Encryption => Icons.lock_outline,
    EventTypes.RoomCreate => Icons.auto_awesome,
    _ => Icons.info_outline,
  };
}

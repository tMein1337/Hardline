import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/util/time_format.dart';
import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';

const _localizations = MatrixDefaultLocalizations();

/// A chat message row.
///
/// Handles both shapes Discord uses: a full row with avatar, name and
/// timestamp when the message starts a block, and a bare continuation line
/// otherwise — indented to align with the text above it, with the timestamp
/// revealed in the left gutter on hover.
class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.event,
    required this.showHeader,
  });

  final Event event;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;
    final sender = event.senderFromMemoryOrFallback;
    final senderName = sender.calcDisplayname();

    // Resolves replies, edits and non-text message types to something
    // presentable, and handles pending sends.
    final body = event.calcLocalizedBodyFallback(
      _localizations,
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
    );

    final isPending = !event.status.isSent;
    final isMention = event.mentions.userIds.contains(event.room.client.userID);

    return Hoverable(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered) {
        return Container(
          color: isMention
              ? (hovered ? colors.mentionHoverBackground : colors.mentionBackground)
              : (hovered ? colors.messageHover : Colors.transparent),
          padding: EdgeInsets.only(
            left: metrics.contentPadding,
            right: metrics.contentPadding,
            top: showHeader ? metrics.messageBlockSpacing : metrics.messageGroupSpacing,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The mention bar Discord draws down the left edge.
              if (isMention)
                Container(
                  width: 2,
                  constraints: const BoxConstraints(minHeight: 20),
                  color: colors.mentionBar,
                  margin: const EdgeInsets.only(right: 6),
                ),
              SizedBox(
                width: metrics.avatarSize,
                child: showHeader
                    ? MxAvatar(
                        name: senderName,
                        seed: event.senderId,
                        mxcUri: sender.avatarUrl?.toString(),
                        size: metrics.avatarSize,
                      )
                    // Continuation: the gutter shows the time on hover only.
                    : Opacity(
                        opacity: hovered ? 1 : 0,
                        child: Text(
                          formatClockTime(event.originServerTs.toLocal()),
                          style: context.text.timestamp.copyWith(fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
              ),
              SizedBox(width: metrics.avatarGutter),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHeader) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              senderName,
                              style: context.text.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatMessageTimestamp(
                              event.originServerTs.toLocal(),
                            ),
                            style: context.text.timestamp,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                    ],
                    SelectableText(
                      body,
                      style: context.text.messageBody.copyWith(
                        color: isPending
                            ? colors.textMuted
                            : context.text.messageBody.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

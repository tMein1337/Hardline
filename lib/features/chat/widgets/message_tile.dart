import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/util/time_format.dart';
import '../../../theme/theme_context.dart';
import '../../activity/widgets/user_context_menu.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import 'message_body.dart';

/// How long the jump-to wash takes to appear and to fade.
const _highlightFade = Duration(milliseconds: 400);

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
    this.highlighted = false,
    this.anchorKey,
  });

  final Event event;
  final bool showHeader;

  /// Whether this is the message somebody jumped to. Washed rather than
  /// outlined, and fades on its own — see `message_list.dart`.
  final bool highlighted;

  /// Scroll target, set only on the highlighted row.
  ///
  /// Cannot be the widget's own `key`: that is already the event id, which is
  /// what keeps element identity stable as the list is rebuilt.
  final GlobalKey? anchorKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;
    final sender = event.senderFromMemoryOrFallback;
    final senderName = sender.calcDisplayname();

    final isPending = !event.status.isSent;
    final isMention = event.mentions.userIds.contains(event.room.client.userID);

    return Hoverable(
      cursor: SystemMouseCursors.basic,
      builder: (context, hovered) {
        // Deliberately not the mention slots. "Someone said your name" and
        // "this is the message you asked for" are different facts, and sharing
        // a colour would make a jump look like a mention.
        final background = highlighted
            ? colors.accent.withValues(alpha: hovered ? 0.22 : 0.16)
            : isMention
            ? (hovered ? colors.mentionHoverBackground : colors.mentionBackground)
            : (hovered ? colors.messageHover : Colors.transparent);

        return AnimatedContainer(
          key: anchorKey,
          duration: _highlightFade,
          curve: Curves.easeOut,
          color: background,
          padding: EdgeInsets.only(
            left: metrics.contentPadding,
            right: metrics.contentPadding,
            top: showHeader ? metrics.messageBlockSpacing : metrics.messageGroupSpacing,
            bottom: 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The mention bar Discord draws down the left edge, reused for the
              // jump target so the row is findable while scrolling past.
              if (isMention || highlighted)
                Container(
                  width: 2,
                  constraints: const BoxConstraints(minHeight: 20),
                  color: highlighted ? colors.accent : colors.mentionBar,
                  margin: const EdgeInsets.only(right: 6),
                ),
              SizedBox(
                width: metrics.avatarSize,
                child: showHeader
                    ? _SenderTarget(
                        event: event,
                        senderName: senderName,
                        sender: sender,
                        child: MxAvatar(
                          name: senderName,
                          seed: event.senderId,
                          mxcUri: sender.avatarUrl?.toString(),
                          size: metrics.avatarSize,
                        ),
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
                            child: _SenderTarget(
                              event: event,
                              senderName: senderName,
                              sender: sender,
                              child: Text(
                                senderName,
                                style: context.text.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                    MessageBody(event: event, isPending: isPending),
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

/// Right-click on a sender's avatar or name opens what can be done about them.
///
/// Secondary tap only: left-clicking a name is how you select text, and taking
/// that over to open a dialog would break copying a message.
class _SenderTarget extends StatelessWidget {
  const _SenderTarget({
    required this.event,
    required this.senderName,
    required this.sender,
    required this.child,
  });

  final Event event;
  final String senderName;
  final User sender;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTap: () => UserContextMenu.show(
        context,
        userId: event.senderId,
        displayName: senderName,
        avatarMxc: sender.avatarUrl?.toString(),
      ),
      child: child,
    );
  }
}

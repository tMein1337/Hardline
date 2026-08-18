// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/util/time_format.dart';
import '../../../theme/theme_context.dart';
import '../../activity/widgets/user_context_menu.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import 'message_body.dart';
import '../../../core/util/display_name.dart';

/// How long the jump-to wash takes to appear and to fade.
const _highlightFade = Duration(milliseconds: 400);

/// A chat message row.
///
/// Handles both shapes a message can take: a full row with avatar, name and
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
    final senderName = displaySafeName(sender.calcDisplayname());

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
              // A double rule down the left edge marks a message that names
              // you, and is reused for the jump target so the row stays
              // findable while scrolling past it.
              if (isMention || highlighted)
                _MentionRule(
                  color: highlighted ? colors.accent : colors.mentionBar,
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

/// Two hairlines with a gap between them, down the left edge of a message.
///
/// A single solid bar is the obvious way to mark a row and is what most clients
/// draw; the split rule reads as a panel marking instead, and stays legible at
/// the accent's brightness where a 2px block of it would glare.
class _MentionRule extends StatelessWidget {
  const _MentionRule({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    // Same box as a plain bar would occupy — only the paint differs — so the
    // row's layout does not depend on which marker is showing.
    return Container(
      width: 4,
      constraints: const BoxConstraints(minHeight: 20),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: const [0.0, 0.25, 0.25, 0.75, 0.75, 1.0],
          colors: [
            color,
            color,
            color.withValues(alpha: 0),
            color.withValues(alpha: 0),
            color,
            color,
          ],
        ),
      ),
    );
  }
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/util/display_name.dart';
import '../../../theme/theme_context.dart';
import '../../activity/activity_navigation.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../timeline_provider.dart';

const _localizations = MatrixDefaultLocalizations();

/// One line of what a message says, for a quote or a banner.
///
/// Plain text with the reply fallback and the edit marker stripped, and line
/// breaks folded into spaces: a quote is a reminder of the message, not the
/// message, and must stay one line high.
String messageSnippet(Event event) => event
    .calcLocalizedBodyFallback(
      _localizations,
      hideReply: true,
      hideEdit: true,
      plaintextBody: true,
    )
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The text of [shown] as its author would edit it: the plain body with any
/// reply fallback removed, line breaks kept.
String editableText(Event shown) => shown.calcLocalizedBodyFallback(
  _localizations,
  hideReply: true,
  hideEdit: true,
  plaintextBody: true,
);

/// The quote above a reply: who it answers, and the first line of what they
/// said. Clicking it jumps to the message.
class ReplyPreview extends ConsumerWidget {
  const ReplyPreview({
    super.key,
    required this.roomId,
    required this.replyToEventId,
  });

  final String roomId;
  final String replyToEventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(timelineControllerProvider(roomId));

    // Loaded is the common case — people answer what is on screen — and is
    // answered synchronously, so the quote does not flicker in on every
    // rebuild of the list.
    final loaded = controller.loadedDisplayEvent(replyToEventId);
    if (loaded != null) return _quote(context, ref, loaded);

    return FutureBuilder<Event?>(
      future: controller.fetchEvent(replyToEventId),
      builder: (context, snapshot) {
        final event = snapshot.data;
        if (event != null) return _quote(context, ref, event);
        return _Line(
          onTap: null,
          child: Text(
            snapshot.connectionState == ConnectionState.done
                ? 'Original message not available'
                : 'Loading reply…',
            style: context.text.timestamp.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      },
    );
  }

  Widget _quote(BuildContext context, WidgetRef ref, Event event) {
    final sender = event.senderFromMemoryOrFallback;
    final name = displaySafeName(sender.calcDisplayname());
    final colors = context.colors;

    return _Line(
      onTap: () => jumpToMessage(ref, roomId, replyToEventId),
      child: Row(
        children: [
          MxAvatar(
            name: name,
            seed: event.senderId,
            mxcUri: sender.avatarUrl?.toString(),
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: context.text.timestamp.copyWith(
              color: colors.textHeader,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              event.redacted ? 'Message deleted' : messageSnippet(event),
              style: context.text.timestamp.copyWith(color: colors.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The shared frame: a hooked rule coming up from the avatar column, then the
/// content, hover-highlighted when it can be clicked.
class _Line extends StatelessWidget {
  const _Line({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Hoverable(
        onTap: onTap,
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: hovered ? colors.accent : colors.dividerStrong,
                width: 2,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

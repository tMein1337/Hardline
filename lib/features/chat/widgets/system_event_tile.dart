// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/util/time_format.dart';
import '../../../theme/theme_context.dart';
import '../../voice/matrix_rtc_membership.dart';
import '../../voice/voice_participants_provider.dart';
import '../../../core/util/display_name.dart';

const _localizations = MatrixDefaultLocalizations();

/// Muted one-liner for joins, leaves, topic changes and similar.
class SystemEventTile extends ConsumerWidget {
  const SystemEventTile({super.key, required this.event});

  final Event event;

  bool get _isRing => kRtcRingEventTypes.contains(event.type);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final metrics = context.metrics;

    // Whether the call this row announced is still going on.
    //
    // There is no "call ended" event to render — MatrixRTC has none, and
    // inventing one would mean every client in the room racing to decide who
    // was last out and Element showing the loser's attempt as an unknown
    // event. The end of a call is not a thing that happens, it is a thing that
    // stops happening, so it is read from the same live membership state the
    // channel list is drawn from rather than from the timeline.
    //
    // Only asked for a ring, and only for the newest one: an old ring is
    // history whatever is happening now.
    final live =
        _isRing &&
        !isRingExpired(event.content, originServerTs: event.originServerTs) &&
        ref.watch(voiceParticipantsProvider(event.roomId ?? '')).isNotEmpty;

    final text = _isRing
        // The SDK has no phrasing for this — it would render "Unknown event
        // org.matrix.msc4075.rtc.notification" — and unlike a member event the
        // body carries no actor, so the name is prefixed here.
        //
        // Deliberately not "video call" or "audio call" even though the ring
        // carries `m.call.intent`: it is regularly the opposite of what the
        // sender's own call membership then advertises, so naming it would be
        // confidently wrong about half the time.
        //
        // The tense matters. Scrolling past "started a call" from three hours
        // ago reads as though one is happening, which is the complaint that a
        // timeline says nothing about calls ending: it was not that the row
        // was missing, it was that the row never stopped being present tense.
        ? '${displaySafeName(event.senderFromMemoryOrFallback.calcDisplayname())} '
              '${live ? 'started a call' : 'called'}'
        // The SDK phrases the rest ("Alice joined the chat"), actor included.
        : event.calcLocalizedBodyFallback(
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
              _isRing ? Icons.call : _iconFor(event.type),
              size: 16,
              // Tinted like every other call affordance in the app. A call
              // starting is worth spotting while scrolling past, where a topic
              // change is not.
              // Green only while it is worth joining. A finished call is
              // history, and history is drawn like the rest of it.
              color: live ? colors.voiceConnected : colors.textFaint,
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
                    style: context.text.timestamp.copyWith(
                      fontSize: context.text.sized(11),
                    ),
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

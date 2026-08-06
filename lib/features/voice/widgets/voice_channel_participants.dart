import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../voice_participants_provider.dart';
import 'voice_participant_row.dart';

/// The people currently in a channel's call, listed under that channel.
///
/// Renders nothing at all when no call is running, which is the common case —
/// a room with no call is byte-identical to how it looked before voice existed.
///
/// This sits *inside* the room list's `itemBuilder` rather than being flattened
/// into the `ListView` as extra items. Flattening would mean maintaining an
/// index-to-(room|participant) mapping that has to be rebuilt on every tick,
/// which fights the snapshot design that keeps the sidebar cheap. A `Column`
/// costs nothing here because the participant count is tiny.
class VoiceChannelParticipants extends ConsumerWidget {
  const VoiceChannelParticipants({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants = ref.watch(voiceParticipantsProvider(roomId));
    if (participants.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final participant in participants.items)
          VoiceParticipantRow(
            key: ValueKey(participant.userId),
            participant: participant,
          ),
      ],
    );
  }
}

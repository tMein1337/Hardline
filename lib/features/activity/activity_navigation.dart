// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// "Take me there" — the point of the activity summary.
///
/// These live here rather than in the rows because opening a room is two
/// selections that must happen together, and a row that got only one of them
/// right would leave the user looking at the correct channel list with the
/// wrong channel open, or vice versa.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/matrix/space_children.dart';
import '../../core/providers/injected_providers.dart';
import '../chat/highlight_provider.dart';
import '../shell/selection_providers.dart';
import '../spaces/space_summary.dart';
import '../voice/join_voice_action.dart';
import '../voice/voice_joinability.dart';

/// Selects [roomId], switching the rail to whichever space holds it first.
///
/// The room list is keyed by space, so selecting a room without selecting its
/// space leaves the selection pointing at a tile that is not in the column.
void openRoom(WidgetRef ref, String roomId) {
  final spaceId =
      spaceIdOfRoom(ref.read(clientProvider), roomId) ?? kHomeSpaceId;

  ref.read(selectedSpaceIdProvider.notifier).select(spaceId);
  ref
      .read(selectedRoomIdsProvider.notifier)
      .select(spaceId: spaceId, roomId: roomId);
}

/// Opens the room and joins its call.
///
/// Goes through `joinVoiceCall` rather than the controller directly, so the
/// power-level consent step comes with it — that dialog exists because joining
/// can permanently change a room for everyone in it, and a second entry point
/// that skipped it would be the one people found.
Future<void> joinFromActivity(
  BuildContext context,
  WidgetRef ref,
  String roomId,
  VoiceJoinability joinability,
) async {
  openRoom(ref, roomId);
  await joinVoiceCall(context, ref, roomId, joinability);
}

/// Opens the room and asks the message list to scroll to [eventId] and mark it.
///
/// The request outlives this call: selecting the room rebuilds the chat panel,
/// so the list that has to act on it does not exist yet.
void jumpToMessage(WidgetRef ref, String roomId, String eventId) {
  openRoom(ref, roomId);
  ref
      .read(highlightedEventProvider.notifier)
      .request(roomId: roomId, eventId: eventId);
}

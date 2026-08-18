// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pending_attachment.dart';

/// How many attachments one message may carry.
///
/// A staging tray is meant to be read at a glance; past this many chips it
/// becomes a list to scroll, and the send is better split in two.
///
/// A cap rather than a warning because the tray holds real bytes for clipboard
/// blobs, and because ten preview chips already overflow the composer.
const kMaxAttachmentsPerMessage = 10;

/// Attachments staged per room, waiting to be sent.
///
/// Keyed by room and deliberately **not** autoDispose, so switching rooms and
/// coming back does not throw away a staged upload. Same shape and same reason
/// as `SelectedRoomIds` in `shell/selection_providers.dart`.
///
/// Neither alternative works here: `timelineControllerProvider` is autoDispose
/// per room, so anything hung off it dies on the switch; and local state in
/// `MessageComposer` would not be per-room at all, because that widget carries
/// no `ValueKey(roomId)` and its `State` is reused across rooms.
class AttachmentDrafts extends Notifier<Map<String, List<PendingAttachment>>> {
  @override
  Map<String, List<PendingAttachment>> build() => const {};

  List<PendingAttachment> forRoom(String roomId) => state[roomId] ?? const [];

  /// Stages [items], keeping the room within [kMaxAttachmentsPerMessage].
  ///
  /// Returns how many were dropped for exceeding the cap, so the caller can say
  /// so rather than letting files disappear without explanation.
  int addAll(String roomId, List<PendingAttachment> items) {
    if (items.isEmpty) return 0;

    final current = forRoom(roomId);
    final room = kMaxAttachmentsPerMessage - current.length;
    if (room <= 0) return items.length;

    final accepted = items.take(room).toList(growable: false);
    state = {
      ...state,
      roomId: [...current, ...accepted],
    };
    return items.length - accepted.length;
  }

  void remove(String roomId, String attachmentId) {
    final current = forRoom(roomId);
    if (current.isEmpty) return;

    final next = current
        .where((attachment) => attachment.id != attachmentId)
        .toList(growable: false);

    // Drop the key entirely when the last one goes, so `state` does not grow a
    // permanent empty entry for every room ever visited.
    state = next.isEmpty
        ? ({...state}..remove(roomId))
        : {...state, roomId: next};
  }

  /// Called after a successful send.
  void clear(String roomId) {
    if (!state.containsKey(roomId)) return;
    state = {...state}..remove(roomId);
  }
}

final attachmentDraftsProvider =
    NotifierProvider<AttachmentDrafts, Map<String, List<PendingAttachment>>>(
      AttachmentDrafts.new,
    );

/// The attachments staged in one room.
///
/// A separate provider so the composer rebuilds only when *its* room's tray
/// changes, not when another room's does.
final roomAttachmentsProvider =
    Provider.family<List<PendingAttachment>, String>((ref, roomId) {
      return ref.watch(attachmentDraftsProvider)[roomId] ?? const [];
    });

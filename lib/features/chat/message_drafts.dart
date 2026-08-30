// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Unsent message text, per room.
///
/// The same shape and the same reasoning as `AttachmentDrafts` next door:
/// keyed by room, and deliberately **not** autoDispose.
///
/// **What this replaces.** The text lived in a `TextEditingController` held as
/// a plain field on `_MessageComposerState`, which meant it survived exactly as
/// long as that `State` did — and that turned out to be far less time than
/// anybody would guess:
///
///  * `ChatPanel` swaps the whole conversation subtree out for `CallGrid` when
///    a call is joined, and back again when the timeline toggle is pressed.
///  * `AppRouter` replaces `HomeShell` outright whenever the bootstrap or
///    account-sync providers re-resolve, which an ordinary settings action can
///    cause — editing a profile invalidates `accountSyncProvider`, and
///    `AppRouter` watches it. That is the settings round-trip in the report.
///  * The composer carries no `ValueKey(roomId)`, so its `State` was *reused*
///    across rooms: a draft typed in one room reappeared in the next. Which is
///    the opposite failure, and was happening at the same time.
///
/// Text is cheap, so unlike the attachment tray there is no cap here beyond
/// dropping the entry when it goes empty.
class MessageDrafts extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  String forRoom(String roomId) => state[roomId] ?? '';

  /// Records what is currently typed in [roomId].
  ///
  /// Clearing the key on empty rather than storing `''` keeps `state` from
  /// growing a permanent entry for every room ever opened, and makes
  /// [hasDraft] a plain key check.
  void set(String roomId, String text) {
    if (text.isEmpty) {
      if (!state.containsKey(roomId)) return;
      state = {...state}..remove(roomId);
      return;
    }
    if (state[roomId] == text) return;
    state = {...state, roomId: text};
  }

  bool hasDraft(String roomId) => state.containsKey(roomId);

  /// Called after a successful send.
  void clear(String roomId) => set(roomId, '');

  /// Forgets everything, for when the setting is switched off.
  ///
  /// Otherwise drafts kept while it was on would go on being restored by the
  /// composer's `initState` — the setting would appear not to take effect until
  /// each room had been visited once more.
  void clearAll() {
    if (state.isEmpty) return;
    state = const {};
  }
}

final messageDraftsProvider =
    NotifierProvider<MessageDrafts, Map<String, String>>(MessageDrafts.new);

/// The draft for one room.
///
/// A separate provider so the composer is not rebuilt by another room's typing.
final roomDraftProvider = Provider.family<String, String>(
  (ref, roomId) => ref.watch(messageDraftsProvider)[roomId] ?? '',
);

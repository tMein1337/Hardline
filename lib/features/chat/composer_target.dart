// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

/// What the composer's next send is about, beyond being a new message.
///
/// Held per room, outside the composer, for the same reason the draft is (see
/// `message_drafts.dart`): the composer's `State` is torn down far more often
/// than anybody would call "leaving the room", and a reply that silently
/// turned into an ordinary message on the way back from settings would be a
/// message sent to the wrong context.
@immutable
sealed class ComposerTarget {
  const ComposerTarget(this.event);

  /// The message this is about — always the *original* event, never the
  /// display copy an edit produces, because relations point at the original
  /// event id.
  final Event event;
}

/// The next message answers [event].
class ReplyTarget extends ComposerTarget {
  const ReplyTarget(super.event);
}

class ComposerTargets extends Notifier<Map<String, ComposerTarget>> {
  @override
  Map<String, ComposerTarget> build() => const {};

  void replyTo(Event event) => _set(event.roomId!, ReplyTarget(event));

  void clear(String roomId) {
    if (!state.containsKey(roomId)) return;
    state = {...state}..remove(roomId);
  }

  void _set(String roomId, ComposerTarget target) =>
      state = {...state, roomId: target};
}

final composerTargetsProvider =
    NotifierProvider<ComposerTargets, Map<String, ComposerTarget>>(
      ComposerTargets.new,
    );

/// The target for one room, or null for an ordinary message.
final composerTargetProvider = Provider.family<ComposerTarget?, String>(
  (ref, roomId) => ref.watch(composerTargetsProvider)[roomId],
);

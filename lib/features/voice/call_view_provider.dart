// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the chat column is showing the timeline instead of the call grid.
///
/// One flag rather than one per room, because there is one call at a time —
/// the grid can only take over the column of the room whose call we are in, so
/// there is only ever one column with a choice to make.
///
/// Not persisted, and deliberately not reset on leaving. It is a view
/// preference for the session: somebody who wants to read while they talk means
/// it for the next call too, and having it silently snap back would be the kind
/// of small betrayal that makes a control feel unreliable.
class CallViewMode extends Notifier<bool> {
  @override
  bool build() => false;

  void showTimeline() => state = true;
  void showCall() => state = false;
  void toggle() => state = !state;
}

/// True when the user has asked for the timeline over the call grid.
final timelinePreferredProvider = NotifierProvider<CallViewMode, bool>(
  CallViewMode.new,
);

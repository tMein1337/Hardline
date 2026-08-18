// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// One row in the message list.
///
/// These hold live `Event` objects, which the SDK mutates. That is safe here
/// only because they live inside a `ChangeNotifier` rather than provider state
/// — see `timeline_controller.dart` for why the timeline is the one place the
/// snapshot approach is deliberately not used.
sealed class TimelineItem {
  const TimelineItem();

  /// Stable identity for list keys.
  String get key;
}

/// A chat message.
class MessageItem extends TimelineItem {
  const MessageItem({required this.event, required this.showHeader});

  final Event event;

  /// False for a continuation line — a message from the same sender close in
  /// time to the one before it, drawn without a repeated avatar and name.
  final bool showHeader;

  @override
  String get key => event.eventId;
}

/// A membership change, topic edit and similar — rendered as a muted one-liner.
class SystemItem extends TimelineItem {
  const SystemItem({required this.event});

  final Event event;

  @override
  String get key => event.eventId;
}

/// The dated rule between two calendar days.
class DateSeparatorItem extends TimelineItem {
  const DateSeparatorItem(this.date);

  final DateTime date;

  @override
  String get key => 'date-${date.year}-${date.month}-${date.day}';
}

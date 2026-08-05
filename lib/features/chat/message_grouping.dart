import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'message_item.dart';

/// How far apart two messages from the same sender may be and still be drawn as
/// one block. This is Discord's actual threshold.
const kGroupWindow = Duration(minutes: 7);

/// State events worth showing inline. Everything else is noise for a chat view.
const _systemEventTypes = {
  EventTypes.RoomMember,
  EventTypes.RoomName,
  EventTypes.RoomTopic,
  EventTypes.RoomCreate,
  EventTypes.Encryption,
  EventTypes.RoomAvatar,
  EventTypes.RoomTombstone,
};

/// The only facts the grouping rule needs about an event.
typedef GroupingEvent = ({String senderId, String type, DateTime timestamp});

/// What the renderer needs to know about one row.
typedef GroupingFlags = ({bool startsGroup, bool crossesDay});

/// Decides which rows start a new visual block and which cross a day boundary.
///
/// Split out from [buildTimelineItems] so the rule can be tested with plain
/// records — building a real `Timeline` would require a `Room`, a `Client` and
/// a database.
///
/// **Ordering contract:** [events] is newest-first, matching
/// `Timeline.events`, and the result is index-aligned with it. So `index + 1`
/// is the *older* neighbour. Getting this backwards yields a chronologically
/// inverted chat that looks plausible until you scroll, which is why
/// `message_grouping_test.dart` asserts the direction explicitly.
@visibleForTesting
List<GroupingFlags> computeGroupingFlags(List<GroupingEvent> events) {
  return [
    for (var i = 0; i < events.length; i++)
      _flagsFor(
        events[i],
        older: i + 1 < events.length ? events[i + 1] : null,
      ),
  ];
}

GroupingFlags _flagsFor(GroupingEvent event, {required GroupingEvent? older}) {
  // The oldest loaded event always starts a block and gets a date rule above it.
  if (older == null) return (startsGroup: true, crossesDay: true);

  final crossesDay = !_isSameDay(event.timestamp, older.timestamp);

  final startsGroup =
      crossesDay ||
      older.senderId != event.senderId ||
      older.type != EventTypes.Message ||
      event.type != EventTypes.Message ||
      event.timestamp.difference(older.timestamp).abs() > kGroupWindow;

  return (startsGroup: startsGroup, crossesDay: crossesDay);
}

/// Turns a timeline into display rows.
List<TimelineItem> buildTimelineItems(Timeline timeline) {
  // Resolve edits and drop rows that are not rendered, so that "the previous
  // message" means the previous *visible* message.
  final visible = <Event>[
    for (final event in timeline.events)
      if (_isRenderable(event)) event.getDisplayEvent(timeline),
  ];

  final flags = computeGroupingFlags([
    for (final event in visible)
      (
        senderId: event.senderId,
        type: event.type,
        timestamp: event.originServerTs,
      ),
  ]);

  final items = <TimelineItem>[];
  for (var i = 0; i < visible.length; i++) {
    final event = visible[i];

    items.add(
      event.type == EventTypes.Message
          ? MessageItem(event: event, showHeader: flags[i].startsGroup)
          : SystemItem(event: event),
    );

    // Appended after, so it renders above this message in the reversed list.
    if (flags[i].crossesDay) items.add(DateSeparatorItem(event.originServerTs));
  }

  return items;
}

bool _isRenderable(Event event) {
  // Edits and reactions are folded into the event they target.
  final relation = event.relationshipType;
  if (relation == RelationshipTypes.edit ||
      relation == RelationshipTypes.reaction) {
    return false;
  }
  if (event.redacted) return false;

  return event.type == EventTypes.Message ||
      _systemEventTypes.contains(event.type);
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

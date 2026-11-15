// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/activity/activity_prefs_controller.dart';
import 'package:hardline/features/chat/widgets/message_list.dart';
import 'package:hardline/features/common/unread_badge.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart' show Room;

import 'support/fakes.dart';
import 'support/live.dart';
import 'support/win32.dart';

// Two people, against a real homeserver.
//
// The activity summary needs somebody else: you cannot follow yourself,
// your own typing is not shown to you, and a mention you send does not badge
// your own room. So this suite has two accounts.
//
//  * **A is the app.** The real `HardlineApp`, in this window, signed in
//    through the real login form, with its data in a temp directory.
//  * **B is a second client** in the same process, driven from the test: it
//    types, it writes, and it is the one who watches A's read receipt move —
//    which is what "Element shows your read receipt moving" was asking.
//
// **Opt-in, and it has to be.** It signs two accounts in to a homeserver,
// makes a room there, and talks in it. It runs only when given a file with
// the two accounts in it:
//
//   flutter drive ... --dart-define=HARDLINE_LIVE_ACCOUNTS=<path to json>
//
// shaped `{"homeserver": "...", "a": {"user", "password"}, "b": {...}}`. That
// file belongs somewhere git ignores. Without it every test here is skipped.
// The room is left and forgotten by both accounts afterwards, and both
// sessions are signed out, so a run leaves no device behind on either.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (liveSkip == null) requireOwnDesktop();

  testWidgets('typing, mentions and read receipts between two people', (
    tester,
  ) async {
    final live = await LiveSession.start(tester);
    addTearDown(live.close);
    final client = live.a;
    final container = live.container;
    final aId = live.aId;
    final bId = live.bId;

    final id = await live.roomWithBoth();
    final bRoom = live.b.getRoomById(id)!;
    await container.read(activityPrefsProvider.notifier).follow(bId);
    await tester.pump(const Duration(milliseconds: 300));

    // ------------------------------------------------------------------
    // Typing.
    // ------------------------------------------------------------------
    // A short timeout and no "stopped" afterwards: the badge has to clear
    // on its own when the homeserver lets the typing lapse, with nothing
    // else arriving to prompt it.
    //
    // Accepting the invitation opened the room, as it should. The summary is
    // what Home shows with no room selected, so go there the way a person
    // would: Home on the rail, pressed while already on Home.
    await tester.tap(find.byTooltip('Home'));
    await pumpUntil(
      tester,
      () => find.text('Activity').evaluate().isNotEmpty,
      reason: 'the activity summary on Home',
    );

    await bRoom.setTyping(true, timeout: 5000);
    // Two waits rather than one, so a failure says which half it was: the
    // homeserver not delivering the typing, or the summary not drawing it.
    await pumpUntil(
      tester,
      () => client.getRoomById(id)!.typingUsers.any((u) => u.id == bId),
      reason: 'A\'s client to receive B\'s typing notification',
      timeout: const Duration(seconds: 30),
    );
    await pumpUntil(
      tester,
      () => find.text('typing…').evaluate().isNotEmpty,
      reason: 'B typing to show on A\'s activity summary',
      timeout: const Duration(seconds: 30),
    );
    final typingSeen = Stopwatch()..start();
    await pumpUntil(
      tester,
      () => find.text('typing…').evaluate().isEmpty,
      reason: 'the typing badge to clear on its own',
      timeout: const Duration(seconds: 40),
    );
    debugPrint(
      '[two users] typing cleared ${typingSeen.elapsedMilliseconds}ms after '
      'it was shown',
    );

    // Sending switches the row to a time, and the message lands in the feed.
    const hello = 'Hello from the second user';
    await bRoom.sendTextEvent(hello);
    await pumpUntil(
      tester,
      () => find.text(hello).evaluate().isNotEmpty,
      reason: 'B\'s message to land in A\'s recent messages',
      timeout: const Duration(seconds: 30),
    );
    expect(find.text('typing…'), findsNothing);

    // ------------------------------------------------------------------
    // Mentions and read receipts.
    // ------------------------------------------------------------------
    // Enough history that the open room can be scrolled away from its
    // newest end.
    for (var i = 1; i <= 40; i++) {
      await bRoom.sendTextEvent('Filler $i');
    }

    Future<String> mention(String text) async {
      final eventId = await bRoom.sendEvent({
        'msgtype': 'm.text',
        'body': '$aId $text',
        'm.mentions': {
          'user_ids': [aId],
        },
      });
      return eventId!;
    }

    Room aRoom() => client.getRoomById(id)!;

    final first = await mention('are you there?');
    await pumpUntil(
      tester,
      () => aRoom().highlightCount > 0,
      reason: 'the mention to badge the room for A',
      timeout: const Duration(seconds: 30),
    );
    final tile = find.byKey(Key('room_tile_$id'));
    await pumpUntil(
      tester,
      () => find
          .descendant(of: tile, matching: find.byType(UnreadBadge))
          .evaluate()
          .isNotEmpty,
      reason: 'the badge to be drawn on the room\'s row',
    );

    // Opening the room clears it, and B sees A's receipt arrive.
    await tester.tap(tile);
    await pumpUntil(
      tester,
      () => aRoom().highlightCount == 0 && aRoom().notificationCount == 0,
      reason: 'opening the room to clear the badge',
      timeout: const Duration(seconds: 30),
    );
    await pumpUntil(
      tester,
      () => bRoom.receiptState.global.otherUsers[aId]?.eventId == first,
      reason: 'B to see A\'s read receipt on the mention',
      timeout: const Duration(seconds: 30),
    );

    // Up in history, a new mention must *not* be marked read.
    final scrollable = find.descendant(
      of: find.byType(MessageList),
      matching: find.byType(Scrollable),
    );
    ScrollPosition position() =>
        tester.state<ScrollableState>(scrollable.first).position;
    await tester.drag(find.byType(MessageList), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(
      position().pixels,
      greaterThan(200),
      reason: 'the list should be scrolled away from the newest message',
    );

    await mention('still there?');
    await pumpUntil(
      tester,
      () => aRoom().highlightCount > 0,
      reason: 'the second mention to badge the room',
      timeout: const Duration(seconds: 30),
    );
    final held = Stopwatch()..start();
    while (held.elapsed < const Duration(seconds: 5)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      aRoom().highlightCount,
      greaterThan(0),
      reason: 'scrolled up into history, the new mention has not been read',
    );

    // Back down to the newest end, and it clears.
    position().jumpTo(0);
    await pumpUntil(
      tester,
      () => aRoom().highlightCount == 0,
      reason: 'scrolling back down to clear the badge',
      timeout: const Duration(seconds: 30),
    );

    // Minimised, a mention survives.
    appWindow.minimize();
    // No frames while minimised — the engine does not draw a window that is
    // not on screen — so this waits on the clock rather than on pumps.
    final hidden = Stopwatch()..start();
    while (!appWindow.isMinimized && hidden.elapsed.inSeconds < 5) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));

    await mention('the window is down');
    final arrived = Stopwatch()..start();
    while (aRoom().highlightCount == 0 && arrived.elapsed.inSeconds < 30) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(aRoom().highlightCount, greaterThan(0), reason: 'it arrived');
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(
      aRoom().highlightCount,
      greaterThan(0),
      reason: 'a mention that arrived while minimised has not been read',
    );

    // And coming back to the open room reads it, with nothing else arriving.
    appWindow.restore();
    await pumpUntil(
      tester,
      () => aRoom().highlightCount == 0,
      reason: 'restoring the window onto the open room to clear the badge',
      timeout: const Duration(seconds: 30),
    );

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: liveSkip != null);
}

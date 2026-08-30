// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/features/rooms/widgets/room_list_title.dart';
import 'package:hardline/features/shell/selection_providers.dart';
import 'package:hardline/features/spaces/space_summary.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';

const _space = '!space:example.org';
const _room = '!room:example.org';

void main() {
  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);

  /// The header, with [openRoom] selected in [spaceId] if given.
  Widget host({
    required String spaceId,
    required String title,
    String? openRoom,
  }) {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    if (openRoom != null) {
      container
          .read(selectedRoomIdsProvider.notifier)
          .select(spaceId: spaceId, roomId: openRoom);
    }

    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: RoomListTitle(title: title, spaceId: spaceId),
        ),
      ),
    );
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(RoomListTitle)),
      );

  testWidgets('shows the name', (tester) async {
    await tester.pumpWidget(host(spaceId: _space, title: 'Friends'));
    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsOneWidget);
  });

  // The bug this exists for. Opening a room filled the chat column with it and
  // nothing brought the space overview back — the rail restores the room you
  // had open, so tapping the space you are already in changes nothing. The
  // list of rooms in a space, and the join button on each of them, were
  // reachable exactly once per session.
  testWidgets('tapping the name reopens the space', (tester) async {
    await tester.pumpWidget(
      host(spaceId: _space, title: 'Friends', openRoom: _room),
    );
    await tester.pumpAndSettle();

    final container = containerOf(tester);
    expect(container.read(selectedRoomIdsProvider)[_space], _room);

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    expect(container.read(selectedRoomIdsProvider)[_space], isNull);
  });

  // Only the space that is showing. Clearing every space's memory would mean
  // one visit to the overview costing your place in all of them.
  testWidgets('leaves the other spaces where they were', (tester) async {
    await tester.pumpWidget(
      host(spaceId: _space, title: 'Friends', openRoom: _room),
    );
    await tester.pumpAndSettle();

    final container = containerOf(tester);
    container
        .read(selectedRoomIdsProvider.notifier)
        .select(spaceId: '!other:example.org', roomId: '!elsewhere:example.org');

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    expect(
      container.read(selectedRoomIdsProvider)['!other:example.org'],
      '!elsewhere:example.org',
    );
  });

  // Nothing to go back to, so nothing to offer. Left as plain text rather than
  // hidden, so the header does not change shape as rooms open and close.
  testWidgets('is inert when no room is open', (tester) async {
    await tester.pumpWidget(host(spaceId: _space, title: 'Friends'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(RoomListTitle),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
  });

  // Home is the same relationship in the same place: the tap goes back to the
  // activity summary rather than to a space overview.
  testWidgets('works on Home too', (tester) async {
    await tester.pumpWidget(
      host(spaceId: kHomeSpaceId, title: 'Home', openRoom: _room),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(
      containerOf(tester).read(selectedRoomIdsProvider)[kHomeSpaceId],
      isNull,
    );
  });
}

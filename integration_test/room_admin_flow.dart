// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/rooms/widgets/room_manage_dialog.dart';
import 'package:hardline/features/shell/selection_providers.dart';
import 'package:hardline/features/spaces/space_rail.dart';
import 'package:hardline/features/spaces/widgets/space_home.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_matrix.dart';
import 'support/fakes.dart';

// Room and space administration in the real window, at the real size, with
// real clicks — against a homeserver that is a `FakeMatrixClient`. The widget
// tests in `test/rooms/` cover every branch of this; what they cannot say is
// whether the dialog fits the window it opens in and whether the things in it
// can actually be reached with a pointer.

const _me = '@me:example.org';
const _alice = '@alice:example.org';
const _room = '!room:example.org';
const _space = '!space:example.org';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  requireOwnDesktop();

  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);
  late FakeMatrixClient client;

  setUp(() => client = FakeMatrixClient(me: _me));

  Future<void> pump(WidgetTester tester, Widget child) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          clientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Waits for something the fake homeserver was asked to do.
  Future<void> sent(WidgetTester tester, String call) => pumpUntil(
    tester,
    () => client.calls.contains(call),
    reason: 'the request "$call" to be sent',
  );

  testWidgets('an admin removes somebody from the member list', (tester) async {
    client.addRoom(_room, name: 'Lobby', levels: {_me: 100}, members: [_alice]);
    client.member(_room, _alice, displayName: 'Alice');

    await pump(
      tester,
      const RoomManageDialog(
        roomId: _room,
        initialSection: RoomManageSection.members,
      ),
    );
    await sent(tester, 'members $_room');

    await tester.tap(find.byKey(const Key('room_member_$_alice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('room_member_kick_$_alice')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Alice?'), findsOneWidget);
    await tester.tap(find.text('Remove').last);
    await sent(tester, 'kick $_room $_alice');

    await pumpUntil(
      tester,
      () => find.byKey(const Key('room_member_$_alice')).evaluate().isEmpty,
      reason: 'the removed member to leave the list',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the three pages fit the window and can be turned', (
    tester,
  ) async {
    client.addRoom(
      _room,
      name: 'Lobby',
      levels: {_me: 100},
      members: [for (var i = 0; i < 40; i++) '@user$i:example.org'],
    );

    await pump(tester, const RoomManageDialog(roomId: _room));
    // Nothing overflowed on the way in: a dialog taller than its window
    // paints the black-and-yellow tape and throws.
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const Key('room_manage_name')), 'Foyer');
    await tester.tap(find.byKey(const Key('room_manage_save')));
    await sent(tester, 'state $_room m.room.name');

    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    // Forty people is more than the dialog is tall. The last one has to be
    // reachable by scrolling, inside the dialog.
    await tester.dragUntilVisible(
      find.byKey(const Key('room_member_@user9:example.org')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Permissions'));
    await tester.pumpAndSettle();
    final row = find.byKey(const Key('room_permission_invite'));
    await tester.tap(
      find.descendant(of: row, matching: find.text('Moderator')),
    );
    await sent(tester, 'state $_room m.room.power_levels');
    expect(
      client
          .getRoomById(_room)!
          .getState(EventTypes.RoomPowerLevels)!
          .content['invite'],
      50,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a room is taken out of a space from the overview', (
    tester,
  ) async {
    client.addRoom(_space, name: 'Games', space: true, levels: {_me: 50});
    client.addRoom(_room, name: 'Lobby');
    client.child(_space, _room);
    client.hierarchyPages[_space] = [
      [FakeMatrixClient.summary(_room, name: 'Lobby')],
    ];

    await pump(tester, const SpaceHome(spaceId: _space));
    expect(find.text('Lobby'), findsOneWidget);

    await tester.tap(find.byKey(const Key('space_remove_$_room')));
    await tester.pumpAndSettle();
    client.hierarchyPages[_space] = [[]];
    await tester.tap(find.text('Take out'));
    await sent(tester, 'state $_space m.space.child $_room');

    await pumpUntil(
      tester,
      () => find.text('Lobby').evaluate().isEmpty,
      reason: 'the room to leave the overview',
    );
    expect(client.getRoomById(_room)!.membership, Membership.join);
  });

  // The decision recorded in `space_tree.dart`: the rail nests, one branch at
  // a time.
  testWidgets('a space inside another appears beneath it when selected', (
    tester,
  ) async {
    client.addRoom(_space, name: 'Games', space: true);
    client.addRoom('!mc:example.org', name: 'Minecraft', space: true);
    client.addRoom('!work:example.org', name: 'Work', space: true);
    client.child(_space, '!mc:example.org');

    await pump(tester, const Row(children: [SpaceRail()]));

    Finder tile(String name) => find.byTooltip(RegExp('^$name\\b'));
    expect(tile('Games'), findsOneWidget);
    expect(tile('Work'), findsOneWidget);
    expect(tile('Minecraft'), findsNothing);

    await tester.tap(tile('Games'));
    await tester.pumpAndSettle();
    expect(tile('Minecraft'), findsOneWidget);
    // Beneath its parent and above the next space, and drawn smaller.
    final games = tester.getRect(tile('Games'));
    final minecraft = tester.getRect(tile('Minecraft'));
    final work = tester.getRect(tile('Work'));
    expect(minecraft.top, greaterThan(games.top));
    expect(work.top, greaterThan(minecraft.top));
    expect(minecraft.height, lessThan(games.height));

    await tester.tap(tile('Work'));
    await tester.pumpAndSettle();
    expect(tile('Minecraft'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SpaceRail)),
    );
    expect(container.read(selectedSpaceIdProvider), '!work:example.org');
  });
}

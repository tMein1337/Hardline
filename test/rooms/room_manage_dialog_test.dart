// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/chat/widgets/chat_header.dart';
import 'package:hardline/features/rooms/room_list_provider.dart';
import 'package:hardline/features/rooms/widgets/room_manage_dialog.dart';
import 'package:hardline/features/spaces/widgets/invite_people_dialog.dart';
import 'package:hardline/features/spaces/widgets/space_home.dart';
import 'package:hardline/features/voice/call_controller_provider.dart';
import 'package:hardline/features/voice/livekit_call_controller.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:matrix/matrix.dart' hide Visibility;

import '../support/fake_matrix.dart';

const _me = '@me:example.org';
const _alice = '@alice:example.org';
const _bob = '@bob:example.org';
const _room = '!room:example.org';
const _space = '!space:example.org';

/// No call anywhere, which is all the chat header asks of the controller.
class _NoCall extends ChangeNotifier implements LiveKitCallController {
  @override
  bool isInCallFor(String roomId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);

  late FakeMatrixClient client;

  setUp(() => client = FakeMatrixClient(me: _me));

  /// Mounts [child] over the fake homeserver, in a window with room for a
  /// dialog.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Future<String?> Function()? pickImage,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clientProvider.overrideWithValue(client),
          callControllerProvider.overrideWithValue(_NoCall()),
          if (pickImage != null)
            roomAvatarPickerProvider.overrideWithValue(pickImage),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open(
    WidgetTester tester, {
    String roomId = _room,
    RoomManageSection section = RoomManageSection.settings,
    Future<String?> Function()? pickImage,
    bool keepCalls = false,
  }) async {
    await pump(
      tester,
      RoomManageDialog(roomId: roomId, initialSection: section),
      pickImage: pickImage,
    );
    await settle(tester);
    // Opening the dialog asks the server two things — whether the room is in
    // the directory, and who is in it. The tests below are about what is
    // sent when something is *changed*.
    if (!keepCalls) client.calls.clear();
  }

  group('settings', () {
    // Somebody with no power sees their way out and nothing else. A control
    // that fails on the click reads as the app being broken.
    testWidgets('a member is shown what is set and offered none of it', (
      tester,
    ) async {
      client.addRoom(_room, name: 'Lobby', members: [_alice]);
      client.state(_room, EventTypes.RoomTopic, {'topic': 'Say hello'});
      await open(tester);

      expect(find.byKey(const Key('room_manage_name')), findsNothing);
      expect(find.byKey(const Key('room_manage_save')), findsNothing);
      expect(find.byKey(const Key('room_manage_picture')), findsNothing);
      expect(find.text('Say hello'), findsOneWidget);
      // Told, not offered.
      expect(find.text('WHO CAN JOIN'), findsOneWidget);
      expect(find.text('Anyone'), findsNothing);
      expect(find.text('Leave room'), findsOneWidget);
      expect(find.text('Delete room'), findsNothing);
    });

    testWidgets('renaming sends only what changed', (tester) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      await open(tester);

      await tester.enterText(
        find.byKey(const Key('room_manage_name')),
        'Foyer',
      );
      await tester.tap(find.byKey(const Key('room_manage_save')));
      await settle(tester);

      expect(client.calls, ['state $_room m.room.name']);
      expect(find.text('Saved.'), findsOneWidget);
      // The title follows, because the dialog reads the room and not the
      // field.
      expect(find.text('Foyer'), findsWidgets);
    });

    testWidgets('an empty name is refused before it is sent', (tester) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      await open(tester);

      await tester.enterText(find.byKey(const Key('room_manage_name')), '  ');
      await tester.tap(find.byKey(const Key('room_manage_save')));
      await settle(tester);

      expect(client.calls, isEmpty);
      expect(find.text('A room needs a name.'), findsOneWidget);
    });

    testWidgets('who can join is changed by choosing', (tester) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      client.state(_room, EventTypes.RoomJoinRules, {'join_rule': 'invite'});
      await open(tester);

      // No space to refer to, so that answer is not on offer.
      expect(find.text('Anyone in its space'), findsNothing);

      await tester.tap(find.text('Anyone'));
      await settle(tester);

      expect(client.getRoomById(_room)!.joinRules, JoinRules.public);
    });

    testWidgets('a join rule this app does not set is still named', (
      tester,
    ) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      client.state(_room, EventTypes.RoomJoinRules, {'join_rule': 'knock'});
      await open(tester);

      expect(
        find.text('People ask to join, and somebody lets them in'),
        findsOneWidget,
      );
    });

    testWidgets('what new members can read is changed by choosing', (
      tester,
    ) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      await open(tester);

      await tester.ensureVisible(find.text('From when they joined'));
      await tester.tap(find.text('From when they joined'));
      await settle(tester);

      expect(
        client.getRoomById(_room)!.historyVisibility,
        HistoryVisibility.joined,
      );
    });

    // A space holds no conversation, so there is no history to show anybody.
    testWidgets('a space is not asked about history', (tester) async {
      client.addRoom(_space, name: 'Games', space: true, levels: {_me: 100});
      await open(tester, roomId: _space);

      expect(find.text('WHAT NEW MEMBERS CAN READ'), findsNothing);
      expect(find.text('WHO CAN JOIN'), findsOneWidget);
      expect(find.text('Leave space'), findsOneWidget);
    });

    testWidgets('the directory switch asks the server, then tells it', (
      tester,
    ) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      await open(tester);

      final listed = find.byKey(const Key('room_manage_listed'));
      await tester.ensureVisible(listed);
      await tester.tap(listed);
      await settle(tester);

      expect(client.listed, contains(_room));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });

    testWidgets('a picture is picked, uploaded and set', (tester) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      late File image;
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('hardline_avatar');
        addTearDown(() => dir.deleteSync(recursive: true));
        image = File('${dir.path}/cat.png')..writeAsBytesSync([1, 2, 3, 4]);
      });
      await open(tester, pickImage: () async => image.path);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('room_manage_picture')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle(tester);

      expect(client.calls, ['upload cat.png 4b', 'state $_room m.room.avatar']);
    });

    testWidgets('cancelling the picker sends nothing', (tester) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      await open(tester, pickImage: () async => null);

      await tester.tap(find.byKey(const Key('room_manage_picture')));
      await settle(tester);

      expect(client.calls, isEmpty);
    });

    testWidgets('a refusal from the server is said in words', (tester) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      client.refuse['state'] = FakeMatrixClient.forbidden();
      await open(tester);

      await tester.tap(find.text('Anyone'));
      await settle(tester);

      expect(
        find.text('The homeserver refused that — you may not have permission.'),
        findsOneWidget,
      );
    });

    // A direct chat is a person before it is a room: two people, nothing to
    // configure.
    testWidgets('a direct chat keeps its one page', (tester) async {
      client.addRoom(_room, members: [_alice]);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          _alice: [_room],
        },
      );
      await open(tester);

      expect(find.text('Members'), findsNothing);
      expect(find.text('Permissions'), findsNothing);
      expect(find.text('Leave chat'), findsOneWidget);
    });
  });

  group('taking a room out of a space', () {
    setUp(() {
      client.addRoom(_space, name: 'Games', space: true, levels: {_me: 50});
      client.addRoom(_room, name: 'Lobby', members: [_alice]);
      client.child(_space, _room);
    });

    testWidgets('from the room, with a question that says what it is not', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('In Games'), findsOneWidget);

      await tester.tap(find.byKey(const Key('room_manage_detach_$_space')));
      await settle(tester);
      expect(find.textContaining('everybody stays in it'), findsOneWidget);
      expect(client.calls, isEmpty, reason: 'nothing before the answer');

      await tester.tap(find.text('Take out').last);
      await settle(tester);

      expect(client.calls.first, 'state $_space m.space.child $_room');
      expect(find.text('In Games'), findsNothing);
      expect(client.getRoomById(_room)!.membership, Membership.join);
    });

    testWidgets('is not offered without power in the space', (tester) async {
      client.state(_space, EventTypes.RoomPowerLevels, {
        'users': {_me: 0},
        'state_default': 50,
      });
      await open(tester);

      expect(find.text('In Games'), findsOneWidget);
      expect(find.byKey(const Key('room_manage_detach_$_space')), findsNothing);
    });

    testWidgets('from the space overview', (tester) async {
      client.hierarchyPages[_space] = [
        [FakeMatrixClient.summary(_room, name: 'Lobby', members: 2)],
      ];
      await pump(tester, const SpaceHome(spaceId: _space));
      await settle(tester);
      expect(find.text('Lobby'), findsOneWidget);
      expect(find.text('1 room in here.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('space_remove_$_room')));
      await settle(tester);
      // The overview is a fetch; once the room is gone the server stops
      // listing it.
      client.hierarchyPages[_space] = [[]];
      await tester.tap(find.text('Take out'));
      await settle(tester);

      expect(client.calls.where((call) => call.startsWith('state')), [
        'state $_space m.space.child $_room',
      ]);
      expect(find.text('Lobby'), findsNothing);
    });
  });

  group('a parent the room names', () {
    testWidgets('can be joined from the room', (tester) async {
      client.addRoom(_room, name: 'Lobby');
      client.state(_room, EventTypes.SpaceParent, {
        'via': ['other.org'],
      }, stateKey: '!elsewhere:other.org');
      await open(tester);

      expect(
        find.text('Says it is part of a space you are not in'),
        findsOneWidget,
      );
      await tester.tap(find.text('Join it'));
      await settle(tester);

      expect(client.calls, ['join !elsewhere:other.org via=other.org']);
    });
  });

  group('members', () {
    setUp(() {
      client.addRoom(
        _room,
        name: 'Lobby',
        levels: {_me: 100},
        members: [_alice, _bob],
      );
      client.member(_room, _alice, displayName: 'Alice');
      client.member(_room, _bob, displayName: 'Bob');
    });

    Finder row(String userId) => find.byKey(Key('room_member_$userId'));

    testWidgets('lists everybody, and says who this account is', (
      tester,
    ) async {
      await open(tester, section: RoomManageSection.members);

      expect(row(_alice), findsOneWidget);
      expect(row(_bob), findsOneWidget);
      expect(find.textContaining('(you)'), findsOneWidget);
      expect(find.text('3 people in here.'), findsOneWidget);
      // The id as well as the name: this is the list people are removed from.
      expect(find.text(_alice), findsOneWidget);
    });

    testWidgets('fetches the people sync never delivered', (tester) async {
      client.unloadedMembers[_room] = [
        FakeMatrixClient.memberEvent(
          '@quiet:example.org',
          displayName: 'Quiet',
        ),
      ];
      await open(tester, section: RoomManageSection.members, keepCalls: true);

      expect(client.calls, ['members $_room']);
      expect(row('@quiet:example.org'), findsOneWidget);
    });

    testWidgets('removing asks first, then removes', (tester) async {
      await open(tester, section: RoomManageSection.members);
      client.calls.clear();

      await tester.tap(row(_alice));
      await settle(tester);
      await tester.tap(find.byKey(const Key('room_member_kick_$_alice')));
      await settle(tester);
      expect(find.text('Remove Alice?'), findsOneWidget);
      expect(client.calls, isEmpty);

      await tester.tap(find.text('Remove').last);
      await settle(tester);

      expect(client.calls, ['kick $_room $_alice']);
      expect(row(_alice), findsNothing);
      expect(find.text('Alice was removed.'), findsOneWidget);
    });

    testWidgets('cancelling the question sends nothing', (tester) async {
      await open(tester, section: RoomManageSection.members);
      client.calls.clear();

      await tester.tap(row(_alice));
      await settle(tester);
      await tester.tap(find.byKey(const Key('room_member_kick_$_alice')));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(client.calls, isEmpty);
      expect(row(_alice), findsOneWidget);
    });

    testWidgets('a ban moves them to their own group, and can be lifted', (
      tester,
    ) async {
      await open(tester, section: RoomManageSection.members);
      client.calls.clear();

      await tester.tap(row(_alice));
      await settle(tester);
      await tester.tap(find.byKey(const Key('room_member_ban_$_alice')));
      await settle(tester);
      await tester.tap(find.text('Ban').last);
      await settle(tester);

      expect(client.calls, ['ban $_room $_alice']);
      expect(find.text('BANNED · 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('room_member_unban_$_alice')));
      await settle(tester);

      expect(client.calls.last, 'unban $_room $_alice');
      expect(row(_alice), findsNothing);
    });

    testWidgets('a role is given by choosing it', (tester) async {
      await open(tester, section: RoomManageSection.members);
      client.calls.clear();

      await tester.tap(row(_alice));
      await settle(tester);
      await tester.tap(find.text('Moderator'));
      await settle(tester);

      expect(client.calls, ['state $_room m.room.power_levels']);
      expect(
        client.getRoomById(_room)!.getPowerLevelByUserId(_alice).level,
        50,
      );
      expect(find.text('Alice is now a moderator.'), findsOneWidget);
    });

    // Nobody can change the role of somebody at their own level, so making
    // somebody an admin is not something an admin can take back.
    testWidgets('raising somebody to your own role asks first', (tester) async {
      await open(tester, section: RoomManageSection.members);
      client.calls.clear();

      await tester.tap(row(_alice));
      await settle(tester);
      // The last of them: this account's own row says Admin as well.
      await tester.tap(find.text('Admin').last);
      await settle(tester);

      expect(
        find.textContaining('you will not be able to undo'),
        findsOneWidget,
      );
      expect(client.calls, isEmpty);

      await tester.tap(find.text('Make Admin'));
      await settle(tester);
      expect(
        client.getRoomById(_room)!.getPowerLevelByUserId(_alice).level,
        100,
      );
    });

    testWidgets('stepping down asks first', (tester) async {
      await open(tester, section: RoomManageSection.members);
      client.calls.clear();

      await tester.tap(row(_me));
      await settle(tester);
      await tester.tap(find.text('Moderator'));
      await settle(tester);

      expect(find.text('Step down to Moderator?'), findsOneWidget);
      await tester.tap(find.text('Step down'));
      await settle(tester);
      expect(client.getRoomById(_room)!.ownPowerLevel.level, 50);
    });

    // For most people in most rooms the row is just a name, and it says why.
    testWidgets('a member can open a row and is told there is nothing', (
      tester,
    ) async {
      client.state(_room, EventTypes.RoomPowerLevels, {
        'users': {_bob: 100},
        'state_default': 50,
      });
      await open(tester, section: RoomManageSection.members);

      await tester.tap(row(_alice));
      await settle(tester);

      expect(find.byKey(const Key('room_member_kick_$_alice')), findsNothing);
      expect(find.byKey(const Key('room_member_ban_$_alice')), findsNothing);
      expect(find.textContaining('needs a role above theirs'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('search narrows the list', (tester) async {
      await open(tester, section: RoomManageSection.members);

      await tester.enterText(
        find.byKey(const Key('room_members_search')),
        'ali',
      );
      await settle(tester);

      expect(row(_alice), findsOneWidget);
      expect(row(_bob), findsNothing);
      expect(find.text('1 of 3 shown.'), findsOneWidget);
    });

    testWidgets('a refused removal leaves them where they were', (
      tester,
    ) async {
      await open(tester, section: RoomManageSection.members);
      client.refuse['kick'] = FakeMatrixClient.forbidden();

      await tester.tap(row(_alice));
      await settle(tester);
      await tester.tap(find.byKey(const Key('room_member_kick_$_alice')));
      await settle(tester);
      await tester.tap(find.text('Remove').last);
      await settle(tester);

      expect(row(_alice), findsOneWidget);
      expect(find.byKey(const Key('room_manage_error')), findsOneWidget);
    });

    testWidgets('the chat header opens straight onto this page', (
      tester,
    ) async {
      await pump(
        tester,
        const ChatHeader(
          header: RoomHeader(
            id: _room,
            name: 'Lobby',
            topic: '',
            isEncrypted: false,
            isDirect: false,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('chat_header_members')));
      await settle(tester);

      expect(find.byKey(const Key('room_members_search')), findsOneWidget);
    });

    testWidgets('and is not there for a direct chat', (tester) async {
      await pump(
        tester,
        const ChatHeader(
          header: RoomHeader(
            id: _room,
            name: 'Alice',
            topic: '',
            isEncrypted: false,
            isDirect: true,
          ),
        ),
      );
      expect(find.byKey(const Key('chat_header_members')), findsNothing);
    });
  });

  group('permissions', () {
    Finder choice(String permission, String role) => find.descendant(
      of: find.byKey(Key('room_permission_$permission')),
      matching: find.text(role),
    );

    // Readable by everybody: "why can I not rename this" has an answer, and
    // this is where it is.
    testWidgets('a member reads them and can change none', (tester) async {
      client.addRoom(_room, name: 'Lobby');
      await open(tester, section: RoomManageSection.permissions);

      expect(find.textContaining('Your role here is Member'), findsOneWidget);
      expect(choice('kick', 'Moderator'), findsOneWidget);
      // Words, not controls: nothing else in the row to click.
      expect(choice('kick', 'Admin'), findsNothing);
      expect(choice('kick', 'Member'), findsNothing);
    });

    testWidgets('an admin changes one by choosing', (tester) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      await open(tester, section: RoomManageSection.permissions);

      await tester.tap(choice('invite', 'Moderator'));
      await settle(tester);

      expect(client.calls, ['state $_room m.room.power_levels']);
      final content = client
          .getRoomById(_room)!
          .getState(EventTypes.RoomPowerLevels)!
          .content;
      expect(content['invite'], 50);
      expect(content['kick'], 50);
    });

    // Being allowed to edit permissions is not being allowed to edit all of
    // them, or to set one above your own role.
    testWidgets('a moderator sees only what is within reach', (tester) async {
      client.addRoom(
        _room,
        name: 'Lobby',
        levels: {_me: 50},
        events: {'m.room.power_levels': 50},
        powerLevels: {'ban': 100},
      );
      await open(tester, section: RoomManageSection.permissions);

      expect(choice('kick', 'Member'), findsOneWidget);
      expect(choice('kick', 'Moderator'), findsOneWidget);
      expect(choice('kick', 'Admin'), findsNothing);
      // Already above them: text only.
      expect(choice('ban', 'Admin'), findsOneWidget);
      expect(choice('ban', 'Member'), findsNothing);
    });

    testWidgets('handing the page to everybody asks first', (tester) async {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      await open(tester, section: RoomManageSection.permissions);

      final target = choice('permissions', 'Member');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await settle(tester);

      expect(find.text('Let every member change permissions?'), findsOneWidget);
      expect(client.calls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(client.calls, isEmpty);
    });

    testWidgets('a space is asked about its rooms and not about calls', (
      tester,
    ) async {
      client.addRoom(_space, name: 'Games', space: true, levels: {_me: 100});
      await open(
        tester,
        roomId: _space,
        section: RoomManageSection.permissions,
      );

      expect(find.text('Add and remove rooms'), findsOneWidget);
      expect(find.text('Join and start calls'), findsNothing);
    });
  });

  group('inviting', () {
    setUp(() {
      client.addRoom(_room, name: 'Lobby', levels: {_me: 100});
      client.addRoom('!other:x', members: [_alice, _bob]);
      client.member('!other:x', _alice, displayName: 'Alice');
      client.member('!other:x', _bob, displayName: 'Bob');
    });

    Future<void> openInvite(WidgetTester tester) => pump(
      tester,
      const InvitePeopleDialog(
        roomId: _room,
        roomName: 'Lobby',
        isSpace: false,
      ),
    );

    // Nearly everybody somebody wants to invite is already in a room with
    // them, and their id is sitting in local state.
    testWidgets('offers people from other rooms as a name is typed', (
      tester,
    ) async {
      await openInvite(tester);
      expect(find.byKey(const Key('invite_suggestion_$_alice')), findsNothing);

      await tester.enterText(find.byType(TextField), 'ali');
      await settle(tester);
      expect(
        find.byKey(const Key('invite_suggestion_$_alice')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('invite_suggestion_$_bob')), findsNothing);

      await tester.tap(find.byKey(const Key('invite_suggestion_$_alice')));
      await settle(tester);

      expect(client.calls, ['invite $_room $_alice']);
      expect(find.text('$_alice — invited'), findsOneWidget);
      // And no longer offered: they have an invitation now.
      await tester.enterText(find.byType(TextField), 'ali');
      await settle(tester);
      expect(find.byKey(const Key('invite_suggestion_$_alice')), findsNothing);
    });

    testWidgets('Enter on a name that can only mean one person invites them', (
      tester,
    ) async {
      await openInvite(tester);

      await tester.enterText(find.byType(TextField), 'bob');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(client.calls, ['invite $_room $_bob']);
    });

    testWidgets('the field still takes any id', (tester) async {
      await openInvite(tester);

      await tester.enterText(find.byType(TextField), '@stranger:far.away');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(client.calls, ['invite $_room @stranger:far.away']);
    });

    testWidgets('something that is neither is still explained', (tester) async {
      await openInvite(tester);

      await tester.enterText(find.byType(TextField), 'nobody at all');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(client.calls, isEmpty);
      expect(find.textContaining('A user ID starts with @'), findsOneWidget);
    });
  });
}

/// Lets the sync tick's debounce, the member fetch and any dialog animation
/// run out.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

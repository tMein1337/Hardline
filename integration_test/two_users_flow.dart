// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/app.dart';
import 'package:hardline/bootstrap/matrix_bootstrap.dart';
import 'package:hardline/bootstrap/vodozemac_bootstrap.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/accounts/account_entry.dart';
import 'package:hardline/features/accounts/active_client.dart';
import 'package:hardline/features/activity/activity_prefs_controller.dart';
import 'package:hardline/features/auth/login_screen.dart';
import 'package:hardline/features/chat/widgets/message_list.dart';
import 'package:hardline/features/common/unread_badge.dart';
import 'package:hardline/main.dart' show hardlineRoot;
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:matrix/matrix.dart' as mx show Visibility;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/win32.dart';

// Two people, against a real homeserver.
//
// Everything in TODOs.md 2 needs somebody else: you cannot follow yourself,
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

const _accountsPath = String.fromEnvironment('HARDLINE_LIVE_ACCOUNTS');

/// See `locked_launch_flow.dart`: the platform instance, not a channel.
class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// The accounts file, read once.
class _Accounts {
  _Accounts(Map<String, Object?> json)
    : homeserver = json['homeserver']! as String,
      aUser = (json['a']! as Map)['user']! as String,
      aPassword = (json['a']! as Map)['password']! as String,
      bUser = (json['b']! as Map)['user']! as String,
      bPassword = (json['b']! as Map)['password']! as String;

  final String homeserver;
  final String aUser;
  final String aPassword;
  final String bUser;
  final String bPassword;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final skip = _accountsPath.isEmpty
      ? 'needs --dart-define=HARDLINE_LIVE_ACCOUNTS=<file>'
      : false;

  if (skip == false) requireOwnDesktop();

  testWidgets('typing, mentions and read receipts between two people', (
    tester,
  ) async {
    final accounts = _Accounts(
      jsonDecode(File(_accountsPath).readAsStringSync())
          as Map<String, Object?>,
    );

    final realPaths = PathProviderPlatform.instance;
    final support = Directory.systemTemp.createTempSync('hardline_two_users');
    PathProviderPlatform.instance = _TempPathProvider(support.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final encryption = await initEncryption();

    // B first, so the room exists before A has anything to look at.
    final b = await buildMatrixClient(
      encryptionAvailable: encryption,
      storageKey: 'liveb',
    );
    await b.checkHomeserver(Uri.parse(accounts.homeserver));
    await b.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: accounts.bUser),
      password: accounts.bPassword,
      initialDeviceDisplayName: 'Hardline test (second user)',
    );
    final bId = b.userID!;

    // A, unsigned-in, as `main()` would build it.
    final a = await buildMatrixClient(
      encryptionAvailable: encryption,
      storageKey: kDefaultStorageKey,
    );

    String? roomId;
    addTearDown(() async {
      // Leave nothing on the server: the room is left and forgotten by both,
      // and both sessions signed out so no device lingers on either account.
      final id = roomId;
      for (final client in [a, b]) {
        try {
          if (id != null && client.getRoomById(id) != null) {
            await client.leaveRoom(id);
            await client.forgetRoom(id);
          }
        } catch (error) {
          debugPrint('[two users] leaving the test room failed: $error');
        }
        try {
          if (client.isLogged()) await client.logout();
        } catch (error) {
          debugPrint('[two users] signing out failed: $error');
        }
      }
      await b.dispose();
      PathProviderPlatform.instance = realPaths;
      try {
        support.deleteSync(recursive: true);
      } catch (_) {}
    });

    await tester.pumpWidget(
      hardlineRoot(
        prefs: prefs,
        boot: ActiveClient(client: a, storageKey: kDefaultStorageKey),
        encryptionAvailable: encryption,
        passphrase: null,
      ),
    );
    await pumpUntil(
      tester,
      () => find.byType(LoginScreen).evaluate().isNotEmpty,
      reason: 'the login screen for a client with no session',
    );

    // ------------------------------------------------------------------
    // Signing in, through the form.
    // ------------------------------------------------------------------
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), Uri.parse(accounts.homeserver).host);
    await tester.enterText(fields.at(1), accounts.aUser);
    await tester.enterText(fields.at(2), accounts.aPassword);
    await tester.tap(find.text('Log In'));
    await pumpUntil(
      tester,
      () => find.byType(LoginScreen).evaluate().isEmpty,
      reason: 'A to be signed in and past the login screen',
      timeout: const Duration(seconds: 60),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HardlineApp)),
    );
    final client = container.read(clientProvider);
    final aId = client.userID!;
    debugPrint('[two users] A is $aId, B is $bId');

    // ------------------------------------------------------------------
    // A room for the two of them, made by B, joined by A from the list.
    // ------------------------------------------------------------------
    // Public join rule, but not published. A server configured to encrypt
    // invite-only rooms by default would otherwise encrypt this one — and the
    // homeserver cannot see a mention inside an encrypted message, so the
    // badge this test is about would never come from the server at all.
    final id = roomId = await b.createRoom(
      name: 'Hardline test ${DateTime.now().toIso8601String()}',
      preset: CreateRoomPreset.publicChat,
      visibility: mx.Visibility.private,
      invite: [aId],
    );

    await pumpUntil(
      tester,
      () => find.text('Accept').evaluate().isNotEmpty,
      reason: 'B\'s invitation to arrive in A\'s room list',
      timeout: const Duration(seconds: 60),
    );
    await tester.tap(find.text('Accept').first);
    await pumpUntil(
      tester,
      () => client.getRoomById(id)?.membership == Membership.join,
      reason: 'A to have joined',
      timeout: const Duration(seconds: 60),
    );
    // B holds the room as "partial" until it is loaded, and the SDK drops
    // membership events for a partial room — so B is told to load it, as a
    // client with the room open would be, and asked for the count.
    await b.getRoomById(id)!.postLoad();
    await pumpUntil(
      tester,
      () => b.getRoomById(id)?.summary.mJoinedMemberCount == 2,
      reason: 'B to have seen A join',
      timeout: const Duration(seconds: 60),
    );
    expect(
      b.getRoomById(id)!.encrypted,
      isFalse,
      reason:
          'The homeserver encrypted the test room. A mention inside an '
          'encrypted message cannot badge anything server-side, so this run '
          'would prove nothing about badges.',
    );
    final bRoom = b.getRoomById(id)!;

    await container.read(activityPrefsProvider.notifier).follow(bId);
    await tester.pump(const Duration(milliseconds: 300));

    // ------------------------------------------------------------------
    // TODOs.md 2.1: typing.
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
    // TODOs.md 2.2: mentions and read receipts.
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
  }, skip: skip != false);
}

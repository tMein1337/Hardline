// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Two people on a real homeserver: the app as one, a second client as the
/// other.
///
/// Shared by the suites that need somebody else — `two_users_flow.dart`,
/// `call_flow.dart`. See the first for why each half is what it is.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/app.dart';
import 'package:hardline/bootstrap/matrix_bootstrap.dart';
import 'package:hardline/bootstrap/vodozemac_bootstrap.dart';
import 'package:hardline/core/providers/bootstrap_provider.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/features/accounts/account_entry.dart';
import 'package:hardline/features/accounts/active_client.dart';
import 'package:hardline/features/auth/login_screen.dart';
import 'package:hardline/main.dart' show hardlineRoot;
import 'package:matrix/matrix.dart' hide Visibility;
import 'package:matrix/matrix.dart' as mx show Visibility;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Where the accounts file is, from `--dart-define=HARDLINE_LIVE_ACCOUNTS`.
///
/// Empty means no live run: every test that needs one is skipped.
const liveAccountsPath = String.fromEnvironment('HARDLINE_LIVE_ACCOUNTS');

/// What `skip:` is given by a live test.
const liveSkip = liveAccountsPath == ''
    ? 'needs --dart-define=HARDLINE_LIVE_ACCOUNTS=<file>'
    : null;

/// See `locked_launch_flow.dart`: the platform instance, not a channel.
class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// The two accounts, the app signed in as the first, a client as the second.
class LiveSession {
  LiveSession._({
    required this.tester,
    required this.a,
    required this.b,
    required this.container,
    required this.encryption,
    required PathProviderPlatform realPaths,
    required Directory support,
  }) : _realPaths = realPaths, // ignore: prefer_initializing_formals
       _support = support; // ignore: prefer_initializing_formals

  final WidgetTester tester;

  /// The app's own client, signed in through the login form.
  final Client a;

  /// The second person.
  final Client b;

  /// The app's provider container, for what a test reads or sets directly.
  final ProviderContainer container;

  /// Whether vodozemac loaded, which encrypted rooms need.
  final bool encryption;

  final PathProviderPlatform _realPaths;
  final Directory _support;
  final _rooms = <String>[];

  String get aId => a.userID!;
  String get bId => b.userID!;

  /// Signs B in, starts the app, and signs A in through its login form.
  static Future<LiveSession> start(WidgetTester tester) async {
    final json =
        jsonDecode(File(liveAccountsPath).readAsStringSync())
            as Map<String, Object?>;
    final homeserver = json['homeserver']! as String;
    final accountA = json['a']! as Map;
    final accountB = json['b']! as Map;

    final realPaths = PathProviderPlatform.instance;
    final support = Directory.systemTemp.createTempSync('hardline_live');
    PathProviderPlatform.instance = _TempPathProvider(support.path);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final encryption = await initEncryption();

    // The app remembers per client name that it has run `init()`. A second
    // session in the same process builds a new client under the same name,
    // which would otherwise never be initialised and never sign in.
    resetBootstrapGuard();

    final b = await buildMatrixClient(
      encryptionAvailable: encryption,
      storageKey: 'liveb',
    );
    await b.checkHomeserver(Uri.parse(homeserver));
    await b.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(
        user: accountB['user']! as String,
      ),
      password: accountB['password']! as String,
      initialDeviceDisplayName: 'Hardline test (second user)',
    );

    // A, signed out, as `main()` would build it.
    final unsigned = await buildMatrixClient(
      encryptionAvailable: encryption,
      storageKey: kDefaultStorageKey,
    );

    await tester.pumpWidget(
      hardlineRoot(
        prefs: prefs,
        boot: ActiveClient(client: unsigned, storageKey: kDefaultStorageKey),
        encryptionAvailable: encryption,
        passphrase: null,
      ),
    );
    await pumpUntil(
      tester,
      () => find.byType(LoginScreen).evaluate().isNotEmpty,
      reason: 'the login screen for a client with no session',
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), Uri.parse(homeserver).host);
    await tester.enterText(fields.at(1), accountA['user']! as String);
    await tester.enterText(fields.at(2), accountA['password']! as String);
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
    final session = LiveSession._(
      tester: tester,
      a: container.read(clientProvider),
      b: b,
      container: container,
      encryption: encryption,
      realPaths: realPaths,
      support: support,
    );
    debugPrint('[live] A is ${session.aId}, B is ${session.bId}');
    return session;
  }

  /// A room made by B, with A invited and joined through the room list.
  ///
  /// Public join rule and unpublished by default: a homeserver set to encrypt
  /// invite-only rooms would otherwise encrypt it, and a mention inside an
  /// encrypted message cannot badge anything server-side. [encrypted] asks
  /// for encryption explicitly instead.
  ///
  /// Ordinary members may hold a call membership, as in a room made by this
  /// app — otherwise only B, who made it, could join a call in it.
  Future<String> roomWithBoth({bool encrypted = false}) async {
    final id = await b.createRoom(
      name: 'Hardline test ${DateTime.now().toIso8601String()}',
      preset: encrypted
          ? CreateRoomPreset.privateChat
          : CreateRoomPreset.publicChat,
      visibility: mx.Visibility.private,
      invite: [aId],
      initialState: [
        if (encrypted)
          StateEvent(
            type: EventTypes.Encryption,
            content: {'algorithm': 'm.megolm.v1.aes-sha2'},
          ),
      ],
      powerLevelContentOverride: {
        'events': {'org.matrix.msc3401.call.member': 0},
      },
    );
    _rooms.add(id);

    await pumpUntil(
      tester,
      () => find.text('Accept').evaluate().isNotEmpty,
      reason: 'B\'s invitation to arrive in A\'s room list',
      timeout: const Duration(seconds: 60),
    );
    await tester.tap(find.text('Accept').first);
    await pumpUntil(
      tester,
      () => a.getRoomById(id)?.membership == Membership.join,
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
      encrypted,
      reason: encrypted
          ? 'The room was asked for encryption and does not have it.'
          : 'The homeserver encrypted the test room. A mention inside an '
                'encrypted message cannot badge anything server-side.',
    );
    return id;
  }

  /// Leaves nothing behind: both accounts leave and forget every room this
  /// session made, and both are signed out so no device lingers.
  Future<void> close() async {
    for (final client in [a, b]) {
      for (final id in _rooms) {
        try {
          if (client.getRoomById(id) != null) {
            await client.leaveRoom(id);
            await client.forgetRoom(id);
          }
        } catch (error) {
          debugPrint('[live] leaving $id failed: $error');
        }
      }
      try {
        if (client.isLogged()) await client.logout();
      } catch (error) {
        debugPrint('[live] signing out failed: $error');
      }
    }
    await b.dispose();
    PathProviderPlatform.instance = _realPaths;
    try {
      _support.deleteSync(recursive: true);
    } catch (_) {}
  }
}

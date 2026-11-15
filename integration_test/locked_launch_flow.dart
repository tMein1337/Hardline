// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/bootstrap/matrix_bootstrap.dart';
import 'package:hardline/core/storage/store_cipher.dart';
import 'package:hardline/features/accounts/account_entry.dart';
import 'package:hardline/features/accounts/active_client.dart';
import 'package:hardline/features/auth/login_screen.dart';
import 'package:hardline/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

// A launch with this device's data encrypted, from `main()` to the first
// screen of the app — the real `main`, not a rehearsal of it.
//
// One test, because `main` can be run once in a process: it initialises
// vodozemac, which refuses a second time. Unlocking with the right passphrase
// is `test/auth/unlock_screen_test.dart` and `launch_sequence_test.dart`.
//
// The check asked for was on a throwaway install: lock it, forget the
// passphrase, use "I have lost the passphrase", and confirm the app comes up
// at the login screen with the stores gone. A throwaway install is what the
// temp directory below is. Everything `main` would have found under
// `%APPDATA%` it finds there instead, so nothing of the person running this
// is opened, let alone erased.

/// Points `getApplicationSupportDirectory` at a temp folder.
///
/// The platform instance, not a method channel: path_provider on Windows is
/// implemented in Dart and never goes near one. See the same class in
/// `test/auth/unlock_screen_test.dart`.
class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

const _passphrase = 'correct horse battery staple';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PathProviderPlatform realPaths;
  late Directory support;
  late String storePath;

  setUp(() async {
    realPaths = PathProviderPlatform.instance;
    support = Directory.systemTemp.createTempSync('hardline_locked_launch');
    PathProviderPlatform.instance = _TempPathProvider(support.path);

    // The account list a signed-in installation carries. Erasing has to take
    // it with the stores, or the next launch would look for a database that
    // is no longer there.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'flutter.accounts_v1':
          '{"entries":[{"storageKey":"default","userId":"@a:example.org",'
          '"homeserver":"https://example.org"}],'
          '"activeStorageKey":"default"}',
    });

    // An encrypted store where `main` will look for one.
    sqfliteFfiInit();
    storePath = await accountStorePath(kDefaultStorageKey);
    Directory(File(storePath).parent.path).createSync(recursive: true);
    final db = await openStore(path: storePath, passphrase: _passphrase);
    await db.execute('CREATE TABLE t (k TEXT)');
    await db.close();
    expect(await storeIsEncrypted(storePath), isTrue);
  });

  /// Closes the client `main` built, so the temp directory can be removed.
  Future<void> shutDown(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginScreen)),
    );
    final client = container.read(activeClientProvider).client;
    await tester.pumpWidget(const SizedBox.shrink());
    await client.dispose();
  }

  tearDown(() {
    PathProviderPlatform.instance = realPaths;
    try {
      support.deleteSync(recursive: true);
    } catch (_) {
      // A handle still open on Windows. The directory is in the system temp
      // folder and holds nothing of anybody's.
    }
  });

  testWidgets('a lost passphrase ends at the login screen with nothing left', (
    tester,
  ) async {
    // Not awaited: `main` stops at the lock screen until it is answered.
    final launched = app.main();
    await pumpUntil(
      tester,
      () => find.text('I have lost the passphrase').evaluate().isNotEmpty,
      reason: 'the lock screen to come up for an encrypted store',
    );
    expect(find.byType(LoginScreen), findsNothing);

    await tester.tap(find.text('I have lost the passphrase'));
    await tester.pumpAndSettle();
    // Asked first, and nothing is gone until it is answered.
    expect(File(storePath).existsSync(), isTrue);
    expect(await storeIsEncrypted(storePath), isTrue);

    await tester.tap(find.text('Erase and start over'));
    await launched;
    await pumpUntil(
      tester,
      () => find.byType(LoginScreen).evaluate().isNotEmpty,
      reason: 'the app to come up at the login screen after erasing',
    );

    // The account list went with the store…
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('accounts_v1'), isNull);
    // …and what is at that path now is a fresh store with no passphrase on
    // it, not the old one with the lock taken off.
    expect(await storeIsEncrypted(storePath), isFalse);
    expect(tester.takeException(), isNull);

    await shutDown(tester);
  });
}

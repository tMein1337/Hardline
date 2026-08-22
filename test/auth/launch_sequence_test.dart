// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/app.dart';
import 'package:hardline/core/storage/hardline_store.dart';
import 'package:hardline/core/storage/store_cipher.dart';
import 'package:hardline/features/accounts/account_entry.dart';
import 'package:hardline/features/accounts/active_client.dart';
import 'package:hardline/features/auth/unlock_screen.dart';
import 'package:hardline/features/settings/device_encryption.dart';
import 'package:hardline/main.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A locked launch calls `runApp` twice, and the second call does not start a
/// fresh tree — Flutter reconciles the new root against the old one. Two
/// `ProviderScope`s reconcile into one, and Riverpod then aborts on the change
/// in override count with "Tried to change the number of overrides", leaving a
/// red screen instead of the app.
///
/// `pumpWidget` reconciles exactly the way `runApp` does, so pumping the two
/// real roots in order is the same sequence a locked launch performs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late HardlineStore store;
  late Client client;
  late SharedPreferences prefs;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hardline_launch');
    store = await HardlineStore.init(
      name: 'matrix_client',
      connection: await openStore(
        path: '${dir.path}/matrix_client.sqlite',
        passphrase: 'the right one!',
      ),
      factory: databaseFactoryFfi,
      maxFileSize: 1024,
    );
    client = Client('matrix_client', database: store);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await store.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// The app's root, with a trivial child: what is under test is the scope, not
  /// the shell, and building the real one would need a synced client.
  Widget appRoot(String? passphrase) => hardlineRoot(
    prefs: prefs,
    boot: ActiveClient(client: client, storageKey: kDefaultStorageKey),
    encryptionAvailable: true,
    passphrase: passphrase,
    child: const MaterialApp(home: Scaffold(body: Text('the app'))),
  );

  testWidgets('the app can replace the lock screen at the root', (
    tester,
  ) async {
    await tester.pumpWidget(
      unlockRoot(prefs: prefs, storageKey: kDefaultStorageKey, onDone: (_) {}),
    );
    expect(find.text('Hardline is locked'), findsOneWidget);

    await tester.pumpWidget(appRoot('the right one!'));

    expect(tester.takeException(), isNull);
    expect(find.text('the app'), findsOneWidget);
    expect(find.text('Hardline is locked'), findsNothing);
  });

  // The two scopes must not be the same widget as far as Flutter is concerned.
  // If this ever holds, the assertion above comes back.
  test('the two root scopes cannot be reconciled into each other', () {
    expect(kUnlockScopeKey, isNot(kAppScopeKey));
  });

  testWidgets('the unlocked passphrase reaches the app that follows', (
    tester,
  ) async {
    await tester.pumpWidget(
      unlockRoot(prefs: prefs, storageKey: kDefaultStorageKey, onDone: (_) {}),
    );
    await tester.pumpWidget(appRoot('the right one!'));

    final context = tester.element(find.text('the app'));
    expect(
      ProviderScope.containerOf(
        context,
        listen: false,
      ).read(devicePassphraseProvider),
      'the right one!',
    );
  });

  // The unlocked launch is the one that broke, but an unencrypted install goes
  // straight to the second root with no first one. It has to keep working.
  testWidgets('an unlocked device still boots straight into the app', (
    tester,
  ) async {
    await tester.pumpWidget(appRoot(null));

    expect(tester.takeException(), isNull);
    expect(find.text('the app'), findsOneWidget);
  });
}

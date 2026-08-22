// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/core/storage/store_cipher.dart';
import 'package:hardline/features/accounts/account_entry.dart';
import 'package:hardline/features/auth/unlock_screen.dart';
import 'package:hardline/theme/metrics.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_builder.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points `getApplicationSupportDirectory` at a temp folder.
///
/// Substituting the platform instance rather than mocking a method channel,
/// because path_provider on Windows and Linux is implemented in Dart and never
/// goes near a channel — a channel mock would be silently ignored on exactly
/// the platforms this app ships on.
class _TempPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final theme = buildThemeData(AppPalettes.dark, AppMetrics.standard);
  const passphrase = 'the right one!';

  late Directory support;
  late String storePath;

  setUp(() async {
    support = Directory.systemTemp.createTempSync('hardline_unlock');
    PathProviderPlatform.instance = _TempPathProvider(support.path);

    // The layout `matrix_bootstrap.dart` expects: one sqlite file per account
    // under a `matrix` directory, the default account unsuffixed.
    final root = Directory('${support.path}/matrix')..createSync();
    storePath = '${root.path}/matrix_client.sqlite';

    final db = await openStore(path: storePath, passphrase: passphrase);
    await db.execute('CREATE TABLE t (k TEXT)');
    await db.close();
  });

  tearDown(() {
    try {
      support.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Pumps the lock screen and records what it eventually reports.
  Future<List<UnlockOutcome>> pump(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final outcomes = <UnlockOutcome>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
        child: MaterialApp(
          theme: theme,
          home: UnlockScreen(
            storageKey: kDefaultStorageKey,
            onDone: outcomes.add,
          ),
        ),
      ),
    );
    return outcomes;
  }

  /// Drives frames *and* real time.
  ///
  /// `pumpAndSettle` alone cannot finish anything here. Everything this screen
  /// does is real file I/O — opening a sqlite file, deleting one — which does
  /// not run inside the test's fake-async zone, so the futures never complete
  /// and `pumpAndSettle` waits for a frame that never comes. Interleaving
  /// `runAsync` gives the I/O actual wall-clock time between frames.
  ///
  /// It also cannot use `pumpAndSettle` at the end: once unlocking succeeds the
  /// screen keeps its spinner turning, because in the real app the next thing
  /// that happens is `runApp` replacing this whole tree.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  Future<void> enter(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Unlock'));
    await settle(tester);
  }

  testWidgets('the right passphrase is handed on', (tester) async {
    final outcomes = await pump(tester);

    await enter(tester, passphrase);

    expect(outcomes, hasLength(1));
    expect(outcomes.single.passphrase, passphrase);
    expect(outcomes.single.erased, isFalse);
  });

  testWidgets('the wrong one is refused, and says so', (tester) async {
    final outcomes = await pump(tester);

    await enter(tester, 'not it at all');

    expect(outcomes, isEmpty);
    expect(find.textContaining('does not open'), findsOneWidget);
  });

  // The screen's whole job is to be tried more than once. sqflite's own
  // database cache makes a failed open poison the path, which without
  // `singleInstance: false` in `openStore` would mean the second, correct
  // attempt failing too — a lock screen that stops accepting the passphrase
  // after one typo.
  testWidgets('a typo does not lock the screen up', (tester) async {
    final outcomes = await pump(tester);

    await enter(tester, 'not it at all');
    expect(outcomes, isEmpty);

    await enter(tester, passphrase);
    expect(outcomes.single.passphrase, passphrase);
  });

  testWidgets('an empty passphrase does nothing at all', (tester) async {
    final outcomes = await pump(tester);

    await tester.tap(find.text('Unlock'));
    await settle(tester);

    expect(outcomes, isEmpty);
    expect(find.textContaining('does not open'), findsNothing);
  });

  testWidgets('erasing is confirmed before anything is deleted', (
    tester,
  ) async {
    final outcomes = await pump(tester);

    await tester.tap(find.text('I have lost the passphrase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(outcomes, isEmpty);
    expect(File(storePath).existsSync(), isTrue);
  });

  testWidgets('erasing removes the stores and the account list', (
    tester,
  ) async {
    final outcomes = await pump(
      tester,
      prefs: {
        'flutter.accounts_v1':
            '{"entries":[{"storageKey":"default","userId":"@a:example.org",'
            '"homeserver":"https://example.org"}],'
            '"activeStorageKey":"default"}',
      },
    );

    await tester.tap(find.text('I have lost the passphrase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase and start over'));
    await settle(tester);

    expect(outcomes, hasLength(1));
    expect(outcomes.single.erased, isTrue);
    expect(outcomes.single.passphrase, isNull);
    expect(File(storePath).existsSync(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('accounts_v1'), isNull);
  });
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/storage/store_cipher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hardline_cipher');
    path = '${dir.path}/store.sqlite';
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Windows keeps a handle a moment longer than the close does; a leftover
      // temp directory is not worth failing a test over.
    }
  });

  /// Writes one row so there is something to prove survived.
  Future<void> seed(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS t (k TEXT)');
    await db.insert('t', {'k': 'hello'});
  }

  Future<Object?> readBack(Database db) async =>
      (await db.query('t')).single['k'];

  test('this build can encrypt at all', () async {
    // If this fails, nothing else in the file means anything: plain SQLite
    // accepts `PRAGMA key` and ignores it, so every other test here would pass
    // against a library writing plaintext. The `hooks:` block in pubspec.yaml
    // is what makes it true.
    await expectLater(requireCipherSupport(), completes);
  });

  test('a store opened without a passphrase is a plain SQLite file', () async {
    final db = await openStore(path: path, passphrase: null);
    await seed(db);
    await db.close();

    expect(await storeIsEncrypted(path), isFalse);
    expect(File(path).readAsBytesSync().take(15), 'SQLite format 3'.codeUnits);
  });

  test('a store opened with a passphrase is not', () async {
    final db = await openStore(path: path, passphrase: 'correct horse b');
    await seed(db);
    await db.close();

    expect(await storeIsEncrypted(path), isTrue);
    final reopened = await openStore(path: path, passphrase: 'correct horse b');
    expect(await readBack(reopened), 'hello');
    await reopened.close();
  });

  test('a file that does not exist is not encrypted', () async {
    expect(await storeIsEncrypted('${dir.path}/nothing-here.sqlite'), isFalse);
  });

  test('the wrong passphrase is refused, and so is none at all', () async {
    final db = await openStore(path: path, passphrase: 'the right one!!');
    await seed(db);
    await db.close();

    await expectLater(
      openStore(path: path, passphrase: 'the wrong one!!'),
      throwsA(isA<WrongStorePassphrase>()),
    );
    await expectLater(
      openStore(path: path, passphrase: null),
      throwsA(isA<WrongStorePassphrase>()),
    );
  });

  // The regression that made `singleInstance: false` non-negotiable. sqflite
  // caches open databases by path, and a failed open leaves a broken entry
  // behind — so with the default the *correct* passphrase then fails too, for
  // the life of the process. Somebody mistyping once and being locked out until
  // they restarted would have been near-impossible to diagnose from a report.
  test('a wrong attempt does not spoil the next, correct one', () async {
    final db = await openStore(path: path, passphrase: 'the right one!!');
    await seed(db);
    await db.close();

    await expectLater(
      openStore(path: path, passphrase: 'wrong'),
      throwsA(isA<WrongStorePassphrase>()),
    );

    final second = await openStore(path: path, passphrase: 'the right one!!');
    expect(await readBack(second), 'hello');
    await second.close();
  });

  // `PRAGMA key` takes no bound parameters, so the passphrase is interpolated
  // into SQL. An apostrophe is both extremely likely in a passphrase somebody
  // chose and exactly what breaks a string literal.
  test('a passphrase containing an apostrophe works', () async {
    const passphrase = "it's a 'quoted' one";

    final db = await openStore(path: path, passphrase: passphrase);
    await seed(db);
    await db.close();

    final reopened = await openStore(path: path, passphrase: passphrase);
    expect(await readBack(reopened), 'hello');
    await reopened.close();

    // And it is a real key, not a truncation at the quote.
    await expectLater(
      openStore(path: path, passphrase: 'it'),
      throwsA(isA<WrongStorePassphrase>()),
    );
  });

  test('an existing plain store can be encrypted in place', () async {
    var db = await openStore(path: path, passphrase: null);
    await seed(db);
    await rekeyOpenStore(db, 'a new passphrase');
    await db.close();

    expect(await storeIsEncrypted(path), isTrue);
    db = await openStore(path: path, passphrase: 'a new passphrase');
    expect(await readBack(db), 'hello');
    await db.close();
  });

  test('and decrypted again, with the rows intact', () async {
    var db = await openStore(path: path, passphrase: 'a new passphrase');
    await seed(db);
    await db.close();

    await rekeyStoreAt(path: path, from: 'a new passphrase', to: null);

    expect(await storeIsEncrypted(path), isFalse);
    db = await openStore(path: path, passphrase: null);
    expect(await readBack(db), 'hello');
    await db.close();
  });

  test('and moved from one passphrase to another', () async {
    final db = await openStore(path: path, passphrase: 'the first one!');
    await seed(db);
    await db.close();

    await rekeyStoreAt(path: path, from: 'the first one!', to: 'the second!!');

    await expectLater(
      openStore(path: path, passphrase: 'the first one!'),
      throwsA(isA<WrongStorePassphrase>()),
    );
    final reopened = await openStore(path: path, passphrase: 'the second!!');
    expect(await readBack(reopened), 'hello');
    await reopened.close();
  });

  // The connection the Matrix SDK is holding is the one that gets re-keyed, so
  // it has to keep working across the rewrite. If it did not, turning
  // encryption on would mean tearing the live client down and rebuilding it.
  test('a connection keeps working after being re-keyed under it', () async {
    final db = await openStore(path: path, passphrase: null);
    await seed(db);

    await rekeyOpenStore(db, 'now it is locked');

    await db.insert('t', {'k': 'written after'});
    expect((await db.query('t')).map((r) => r['k']), [
      'hello',
      'written after',
    ]);
    await db.close();

    final reopened = await openStore(
      path: path,
      passphrase: 'now it is locked',
    );
    expect((await reopened.query('t')).length, 2);
    await reopened.close();
  });
}

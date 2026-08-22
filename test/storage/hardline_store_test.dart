// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/storage/hardline_store.dart';
import 'package:hardline/core/storage/store_cipher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hardline_store');
    path = '${dir.path}/store.sqlite';
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // See store_cipher_test.dart.
    }
  });

  Future<HardlineStore> openAt({String? passphrase}) async =>
      HardlineStore.init(
        name: 'test_client',
        connection: await openStore(path: path, passphrase: passphrase),
        factory: databaseFactoryFfi,
        maxFileSize: 10 * 1024 * 1024,
      );

  Uint8List bytes(int length, [int seed = 0]) =>
      Uint8List.fromList(List.generate(length, (i) => (i + seed) % 256));

  final photo = Uri.parse('mxc://example.org/AbCdEf');
  final avatar = Uri.parse('mxc://example.org/ZyXwVu');

  test('caching is on, whatever the SDK would have concluded', () async {
    // The mixin decides this from `fileStorageLocation`, which this store does
    // not set. Answering "no" would silently turn every avatar in the app into
    // a fresh download on every frame that asked for it.
    final store = await openAt();
    expect(store.supportsFileStoring, isTrue);
    await store.close();
  });

  test('an attachment round-trips through the store', () async {
    final store = await openAt();
    final content = bytes(300000);

    await store.storeFile(photo, content, 1000);

    expect(await store.getFile(photo), content);
    expect(await store.getFile(avatar), isNull);
    await store.close();
  });

  test('a cached attachment survives a restart', () async {
    var store = await openAt();
    await store.storeFile(photo, bytes(64), 1000);
    await store.close();

    store = await openAt();
    expect(await store.getFile(photo), bytes(64));
    await store.close();
  });

  test('storing the same URI again refreshes when it was saved', () async {
    final store = await openAt();
    await store.storeFile(photo, bytes(8), 1000);
    await store.storeFile(photo, bytes(8), 5000);

    // Still one row, and now old enough only against a later cutoff.
    await store.deleteOldFiles(4000);
    expect(await store.getFile(photo), isNotNull);

    await store.deleteOldFiles(6000);
    expect(await store.getFile(photo), isNull);
    await store.close();
  });

  test('deleting an attachment reports whether there was one', () async {
    final store = await openAt();
    await store.storeFile(photo, bytes(8), 1000);

    expect(await store.deleteFile(photo), isTrue);
    expect(await store.deleteFile(photo), isFalse);
    expect(await store.getFile(photo), isNull);
    await store.close();
  });

  test('the expiry sweep drops only what is older than the cutoff', () async {
    final store = await openAt();
    await store.storeFile(photo, bytes(8), 1000);
    await store.storeFile(avatar, bytes(8, 1), 9000);

    await store.deleteOldFiles(5000);

    expect(await store.getFile(photo), isNull);
    expect(await store.getFile(avatar), isNotNull);
    await store.close();
  });

  // Both of these used to leave the largest cache in the database behind,
  // because `BoxCollection` only clears the tables it created itself.
  test('clearing the store takes the attachments with it', () async {
    final store = await openAt();
    await store.storeFile(photo, bytes(8), 1000);

    await store.clear();

    expect(await store.getFile(photo), isNull);
    await store.close();
  });

  test('clearing the cache does too', () async {
    final store = await openAt();
    await store.storeFile(photo, bytes(8), 1000);

    await store.clearCache();

    expect(await store.getFile(photo), isNull);
    await store.close();
  });

  // The reason the cache lives in the database at all. An attachment written
  // while the device is locked has to be inside the encrypted file, not beside
  // it, and it has to still be readable once the passphrase is given again.
  test('attachments are inside whatever protects the database', () async {
    var store = await openAt(passphrase: 'a locked device!');
    await store.storeFile(photo, bytes(4096), 1000);
    await store.close();

    expect(await storeIsEncrypted(path), isTrue);
    expect(Directory(dir.path).listSync().whereType<Directory>(), isEmpty);

    await expectLater(
      openStore(path: path, passphrase: null),
      throwsA(isA<WrongStorePassphrase>()),
    );

    store = await openAt(passphrase: 'a locked device!');
    expect(await store.getFile(photo), bytes(4096));
    await store.close();
  });

  // The SDK migrates its schema inside `open()`, and the default migration ends
  // in `clearCache()` — which this class extends to empty the attachment table.
  // Creating that table after `open()` therefore works perfectly until the day
  // the SDK bumps its version, and then stops the app from starting at all.
  test('opening survives the SDK migrating its own schema', () async {
    var store = await openAt();
    await store.storeFile(photo, bytes(8), 1000);
    // Pretend this store was written by an older SDK.
    await store.connection.update(
      'box_client',
      {'v': '10'},
      where: 'k = ?',
      whereArgs: ['version'],
    );
    await store.close();

    store = await openAt();

    // The migration clears caches, the attachment among them, and the point is
    // that it got that far rather than throwing on a missing table.
    expect(await store.getFile(photo), isNull);
    await store.storeFile(photo, bytes(8), 2000);
    expect(await store.getFile(photo), isNotNull);
    await store.close();
  });

  test('an attachment cached before the lock is readable after it', () async {
    var store = await openAt();
    await store.storeFile(photo, bytes(2048), 1000);
    await rekeyOpenStore(store.connection, 'locked from now');
    await store.close();

    store = await openAt(passphrase: 'locked from now');
    expect(await store.getFile(photo), bytes(2048));
    await store.close();
  });
}

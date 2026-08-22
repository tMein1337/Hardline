// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/core/storage/hardline_store.dart';
import 'package:hardline/core/storage/store_cipher.dart';
import 'package:hardline/features/accounts/account_entry.dart';
import 'package:hardline/features/accounts/active_client.dart';
import 'package:hardline/features/settings/device_encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Holds one client still, so the controller has something to re-key.
///
/// The real controller builds and swaps clients; nothing here does either, and
/// overriding `build` is what keeps `bootClientProvider` out of the test.
class _FixedActiveClient extends ActiveClientController {
  _FixedActiveClient(this.active);

  final ActiveClient active;

  @override
  ActiveClient build() => active;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory dir;
  late String path;
  late HardlineStore store;
  late Client client;
  late ProviderContainer container;

  Future<void> start({String? passphrase}) async {
    dir = Directory.systemTemp.createTempSync('hardline_devenc');
    path = '${dir.path}/matrix_client.sqlite';

    store = await HardlineStore.init(
      name: 'matrix_client',
      connection: await openStore(path: path, passphrase: passphrase),
      factory: databaseFactoryFfi,
      maxFileSize: 1024,
    );
    client = Client('matrix_client', database: store);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    container = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(await SharedPreferences.getInstance()),
        bootPassphraseProvider.overrideWithValue(passphrase),
        activeClientProvider.overrideWith(
          () => _FixedActiveClient(
            ActiveClient(client: client, storageKey: kDefaultStorageKey),
          ),
        ),
      ],
    );
  }

  tearDown(() async {
    container.dispose();
    await store.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a device with no passphrase reports itself unencrypted', () async {
    await start();

    expect(container.read(deviceEncryptionEnabledProvider), isFalse);
    expect(await storeIsEncrypted(path), isFalse);
  });

  test('enabling encrypts the store and holds the passphrase', () async {
    await start();

    final ok = await container
        .read(deviceEncryptionProvider.notifier)
        .enable('a good passphrase');

    expect(ok, isTrue);
    expect(await storeIsEncrypted(path), isTrue);
    expect(container.read(devicePassphraseProvider), 'a good passphrase');
    expect(container.read(deviceEncryptionEnabledProvider), isTrue);
    expect(container.read(deviceEncryptionProvider).error, isNull);
    expect(container.read(deviceEncryptionProvider).busy, isFalse);
  });

  // The live client keeps its connection across the re-key, which is the whole
  // reason turning this on does not have to tear the app down and rebuild it.
  test('the store stays usable while it is being encrypted', () async {
    await start();
    await client.database.storeFile(
      Uri.parse('mxc://example.org/before'),
      Uint8List.fromList([1, 2, 3]),
      1000,
    );

    await container
        .read(deviceEncryptionProvider.notifier)
        .enable('a good passphrase');

    await client.database.storeFile(
      Uri.parse('mxc://example.org/after'),
      Uint8List.fromList([4, 5, 6]),
      2000,
    );
    expect(
      await client.database.getFile(Uri.parse('mxc://example.org/before')),
      [1, 2, 3],
    );
    expect(
      await client.database.getFile(Uri.parse('mxc://example.org/after')),
      [4, 5, 6],
    );
  });

  test('changing the passphrase leaves only the new one working', () async {
    await start(passphrase: 'the first one!');

    final ok = await container
        .read(deviceEncryptionProvider.notifier)
        .changePassphrase('the second one!');

    expect(ok, isTrue);
    expect(container.read(devicePassphraseProvider), 'the second one!');

    await store.close();
    await expectLater(
      openStore(path: path, passphrase: 'the first one!'),
      throwsA(isA<WrongStorePassphrase>()),
    );
    store = await HardlineStore.init(
      name: 'matrix_client',
      connection: await openStore(path: path, passphrase: 'the second one!'),
      factory: databaseFactoryFfi,
      maxFileSize: 1024,
    );
  });

  test('disabling puts the store back to a plain file', () async {
    await start(passphrase: 'the first one!');
    expect(container.read(deviceEncryptionEnabledProvider), isTrue);

    final ok = await container
        .read(deviceEncryptionProvider.notifier)
        .disable();

    expect(ok, isTrue);
    expect(await storeIsEncrypted(path), isFalse);
    expect(container.read(devicePassphraseProvider), isNull);
    expect(container.read(deviceEncryptionEnabledProvider), isFalse);
  });

  // A passphrase the app is certain of but which opens nothing is the failure
  // this feature has to avoid above all others, so the flag and the file are
  // never allowed to be set independently.
  test('the held passphrase is what the file is actually keyed with', () async {
    await start();
    await container
        .read(deviceEncryptionProvider.notifier)
        .enable('a good passphrase');
    await store.close();

    final held = container.read(devicePassphraseProvider);
    store = await HardlineStore.init(
      name: 'matrix_client',
      connection: await openStore(path: path, passphrase: held),
      factory: databaseFactoryFfi,
      maxFileSize: 1024,
    );
    expect(store.connection.isOpen, isTrue);
  });
}

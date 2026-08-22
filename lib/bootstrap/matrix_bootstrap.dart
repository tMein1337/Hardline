// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
// `KeyVerificationMethod` lives in the encryption barrel, which `matrix.dart`
// does not re-export.
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/storage/hardline_store.dart';
import '../core/storage/store_cipher.dart';
import '../features/accounts/account_entry.dart';
import '../features/voice/matrix_rtc_membership.dart';

/// Base name used for both the SDK client identity and the database file.
const _baseName = 'matrix_client';

/// Media cache ceiling. Attachments larger than this are re-fetched instead of
/// being stored.
const _maxCachedFileSize = 10 * 1024 * 1024;

/// The one place a storage key becomes a name on disk.
///
/// [kDefaultStorageKey] maps to the original unsuffixed name so the database
/// that existed before multi-account support is adopted as-is — nobody is
/// signed out by upgrading.
String _clientNameFor(String storageKey) =>
    storageKey == kDefaultStorageKey ? _baseName : '$_baseName-$storageKey';

/// Where the attachment cache used to live, before it moved into the database.
///
/// Kept only so it can be cleaned up: see [HardlineStore] for why the files are
/// no longer written here, and [_retireFileCache] for what happens to the ones
/// that already were.
String _legacyFileDirNameFor(String storageKey) =>
    storageKey == kDefaultStorageKey ? 'files' : 'files-$storageKey';

Future<Directory> _storageRoot() async {
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'matrix'));
}

/// The sqlite file one account lives in.
///
/// Public because two callers outside this file need to reason about the file
/// rather than the client: `main()` asks whether it is encrypted before it can
/// know whether to ask for a passphrase, and the security settings re-key the
/// stores of accounts that are not currently open.
Future<String> accountStorePath(String storageKey) async =>
    p.join((await _storageRoot()).path, '${_clientNameFor(storageKey)}.sqlite');

/// Builds the Matrix client for one account, including its persistent store.
///
/// Called from `ActiveClientController`, which is the single owner of live
/// clients — the sequence has hard ordering (ffi before opening sqlite,
/// vodozemac before the client) and two clients must never share a [storageKey],
/// because that would open a second handle on the same database file.
///
/// This does **not** call `client.init()` — restoring the session is slow and
/// failure-prone, so it happens behind a provider that can show a splash and a
/// retry button. See `bootstrap_provider.dart`.
///
/// [storePassphrase] is null unless the user has turned on device encryption,
/// in which case it is the passphrase every one of this installation's stores
/// is keyed with. Passing the wrong one throws [WrongStorePassphrase]; passing
/// none for a store that is encrypted throws it too, because an encrypted file
/// read without a key is not a database.
Future<Client> buildMatrixClient({
  required bool encryptionAvailable,
  required String storageKey,
  String? storePassphrase,
}) async {
  // Registers the FFI sqlite implementation used on desktop. Must precede any
  // openDatabase call.
  sqfliteFfiInit();

  final clientName = _clientNameFor(storageKey);
  final root = await _storageRoot();
  await root.create(recursive: true);

  final database = await HardlineStore.init(
    name: clientName,
    connection: await openStore(
      path: p.join(root.path, '$clientName.sqlite'),
      passphrase: storePassphrase,
    ),
    // Required for database.delete() to work when logging out.
    factory: databaseFactoryFfi,
    maxFileSize: _maxCachedFileSize,
  );

  // The attachment cache used to be a directory of plain files beside the
  // database. It is inside the database now, so whatever is left out there is
  // both stale and the one part of an account not covered by the store's
  // encryption. Removing it is best-effort and off the critical path: a
  // leftover directory is untidy, and failing to launch over it would not be.
  unawaited(_retireFileCache(root, storageKey));

  return Client(
    clientName,
    database: database,
    logLevel: kDebugMode ? Level.warning : Level.error,
    // Rooms start out `partial` and stay that way until their timeline is
    // opened. While partial, the SDK drops every state event that is not on
    // this list (`client.dart`, `_updateRoomsByEventUpdate`), and the database
    // only writes listed types to its preload table (`matrix_sdk_database.dart`)
    // — so an unlisted type is invisible until `postLoad()` runs. That matters
    // for two events:
    //
    //  * the MatrixRTC membership, or we could not show who is in a call in any
    //    room the user has not opened, which is the whole point of the voice
    //    participant list.
    //  * `m.room.power_levels`, or the "can I join this call?" check would read
    //    a missing state event and answer wrongly.
    //
    // Note this is deliberately NOT `EventTypes.GroupCallMember`: that constant
    // is `com.famedly.call.member`, a Famedly-only parallel implementation that
    // no Element client reads or writes. See `matrix_rtc_membership.dart`.
    //
    // The SDK adds its own defaults to whatever set we pass, so this extends
    // rather than replaces them.
    importantStateEvents: {
      kCallMemberEventType,
      EventTypes.RoomPowerLevels,
    },
    // Not optional, and silent when missing: `KeyVerificationManager` returns
    // early on every `m.key.verification.*` to-device event while this set is
    // empty (`key_verification_manager.dart`), so an unset value means incoming
    // verification requests are discarded with no error anywhere.
    //
    // Both methods, and the verification dialog renders both. This set becomes
    // the `short_authentication_string` we offer; the SDK keeps the
    // *intersection* with what the other side offers, so with two full clients
    // emoji and decimal are both agreed and each end picks what to draw.
    // Element draws emoji. Advertising both and rendering only one is what
    // makes a verification impossible to complete — the two people are looking
    // at different things derived from the same secret.
    verificationMethods: {
      KeyVerificationMethod.emoji,
      KeyVerificationMethod.numbers,
    },
    // Moves Olm/Megolm work off the UI thread. The isolate has its own copy of
    // the Rust library state, hence the per-call init hook.
    nativeImplementations: encryptionAvailable
        ? NativeImplementationsIsolate(compute, vodozemacInit: () => vod.init())
        : NativeImplementations.dummy,
  );
}

/// Deletes the attachment directory an older version of Hardline wrote.
///
/// Nothing is lost with it: every byte in there is a cache of something the
/// homeserver still has, and the store fetches it again on demand. What is
/// gained is that an installation which later turns encryption on does not
/// leave a folder of readable photos next to a database nobody can read.
Future<void> _retireFileCache(Directory root, String storageKey) async {
  final legacy = Directory(
    p.join(root.path, _legacyFileDirNameFor(storageKey)),
  );
  try {
    if (await legacy.exists()) await legacy.delete(recursive: true);
  } catch (error) {
    debugPrint('Could not remove the old file cache at ${legacy.path}: $error');
  }
}

/// Removes everything on disk that belonged to one account.
///
/// `Client.logout()` empties the database but leaves the file — so without
/// this, signing out of an account leaves a file behind that a later launch
/// would still find. The attachment directory is listed as well, because an
/// installation upgrading from a version that wrote one may still have it.
///
/// Must run **after** the client has been disposed: Windows keeps the sqlite
/// file locked while a handle is open, and the delete would fail silently.
/// Failures are logged rather than thrown; leftover files are untidy, not
/// broken, and this always runs during a teardown that has to complete.
Future<void> deleteAccountStorage(String storageKey) async {
  final clientName = _clientNameFor(storageKey);
  final root = await _storageRoot();

  final targets = <FileSystemEntity>[
    File(p.join(root.path, '$clientName.sqlite')),
    Directory(p.join(root.path, _legacyFileDirNameFor(storageKey))),
  ];

  for (final target in targets) {
    try {
      if (await target.exists()) {
        await target.delete(recursive: true);
      }
    } catch (error) {
      debugPrint('Could not remove ${target.path}: $error');
    }
  }
}

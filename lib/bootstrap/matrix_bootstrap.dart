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

String _fileDirNameFor(String storageKey) =>
    storageKey == kDefaultStorageKey ? 'files' : 'files-$storageKey';

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
Future<Client> buildMatrixClient({
  required bool encryptionAvailable,
  required String storageKey,
}) async {
  // Registers the FFI sqlite implementation used on desktop. Must precede any
  // openDatabase call.
  sqfliteFfiInit();

  final clientName = _clientNameFor(storageKey);
  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'matrix'));
  final files = Directory(p.join(root.path, _fileDirNameFor(storageKey)));

  // DatabaseFileStorage writes into this directory but does not create it.
  await root.create(recursive: true);
  await files.create(recursive: true);

  final database = await MatrixSdkDatabase.init(
    clientName,
    // Required on native: MatrixSdkDatabase throws if handed a null database.
    database: await databaseFactoryFfi.openDatabase(
      p.join(root.path, '$clientName.sqlite'),
    ),
    // Required for database.delete() to work when logging out.
    sqfliteFactory: databaseFactoryFfi,
    maxFileSize: _maxCachedFileSize,
    fileStorageLocation: files.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
  );

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

/// Removes everything on disk that belonged to one account.
///
/// `Client.logout()` empties the database but leaves the file, and it never
/// touches the media cache directory — so without this, signing out of an
/// account leaves its cached attachments readable by anyone with the machine.
///
/// Must run **after** the client has been disposed: Windows keeps the sqlite
/// file locked while a handle is open, and the delete would fail silently.
/// Failures are logged rather than thrown; leftover files are untidy, not
/// broken, and this always runs during a teardown that has to complete.
Future<void> deleteAccountStorage(String storageKey) async {
  final clientName = _clientNameFor(storageKey);
  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'matrix'));

  final targets = <FileSystemEntity>[
    File(p.join(root.path, '$clientName.sqlite')),
    Directory(p.join(root.path, _fileDirNameFor(storageKey))),
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

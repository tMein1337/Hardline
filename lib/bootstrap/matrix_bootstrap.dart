import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Name used for both the SDK client identity and the database file.
const _clientName = 'matrix_client';

/// Media cache ceiling. Attachments larger than this are re-fetched instead of
/// being stored.
const _maxCachedFileSize = 10 * 1024 * 1024;

/// Builds the Matrix client, including its persistent store.
///
/// Called once from `main()` before `runApp`, because the sequence has hard
/// ordering (ffi before opening sqlite, vodozemac before the client) and
/// because a client that could be rebuilt would open a second handle on the
/// same database file.
///
/// This does **not** call `client.init()` — restoring the session is slow and
/// failure-prone, so it happens behind a provider that can show a splash and a
/// retry button. See `bootstrap_provider.dart`.
Future<Client> buildMatrixClient({required bool encryptionAvailable}) async {
  // Registers the FFI sqlite implementation used on desktop. Must precede any
  // openDatabase call.
  sqfliteFfiInit();

  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'matrix'));
  final files = Directory(p.join(root.path, 'files'));

  // DatabaseFileStorage writes into this directory but does not create it.
  await root.create(recursive: true);
  await files.create(recursive: true);

  final database = await MatrixSdkDatabase.init(
    _clientName,
    // Required on native: MatrixSdkDatabase throws if handed a null database.
    database: await databaseFactoryFfi.openDatabase(
      p.join(root.path, '$_clientName.sqlite'),
    ),
    // Required for database.delete() to work when logging out.
    sqfliteFactory: databaseFactoryFfi,
    maxFileSize: _maxCachedFileSize,
    fileStorageLocation: files.uri,
    deleteFilesAfterDuration: const Duration(days: 30),
  );

  return Client(
    _clientName,
    database: database,
    logLevel: kDebugMode ? Level.warning : Level.error,
    // Moves Olm/Megolm work off the UI thread. The isolate has its own copy of
    // the Rust library state, hence the per-call init hook.
    nativeImplementations: encryptionAvailable
        ? NativeImplementationsIsolate(compute, vodozemacInit: () => vod.init())
        : NativeImplementations.dummy,
  );
}

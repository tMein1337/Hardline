// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Opening, keying and re-keying the sqlite file an account lives in.
//
// The cipher is not ours. `pubspec.yaml` points the `sqlite3` package's build
// hook at SQLite3MultipleCiphers (https://utelle.github.io/SQLite3MultipleCiphers/),
// which is stock SQLite plus page-level encryption reachable through
// `PRAGMA key`. Everything here is the thin, careful layer around that pragma:
// what to pass it, how to tell a wrong passphrase from a broken file, and how
// to turn encryption on for a database that already exists.
//
// Nothing in this file decides *whether* to encrypt. That is `device_lock.dart`'s
// job, and it decides by looking at the file rather than at a setting.

/// The cipher scheme, pinned rather than left to the default.
///
/// `chacha20` (ChaCha20-Poly1305, PBKDF2-SHA256 over a per-database random
/// salt) *is* SQLite3MultipleCiphers' default today. Naming it anyway costs
/// nothing and buys the thing that matters for data at rest: a future release
/// that changed its default would otherwise make every existing database
/// unreadable, silently and with no way back. Written down, a change of scheme
/// becomes a one-line, greppable decision instead of an upgrade that eats
/// people's message history.
const _cipherScheme = 'chacha20';

/// The first bytes of every *unencrypted* SQLite file, per the file format
/// spec. An encrypted database has ciphertext here instead, which makes the
/// file itself the honest answer to "is this store encrypted", with no
/// preference to fall out of sync with reality.
const _plainTextHeader = 'SQLite format 3';

/// The bundled SQLite has no cipher in it.
///
/// This is the failure that must never be silent: plain SQLite accepts
/// `PRAGMA key` and *ignores it*, so a build that lost the SQLite3MultipleCiphers
/// library would cheerfully write everything in the clear while the app showed
/// a padlock. Every keyed path checks first and refuses.
class StoreCipherUnavailable implements Exception {
  const StoreCipherUnavailable();

  @override
  String toString() =>
      'The bundled SQLite has no encryption support. Hardline will not open an '
      'encrypted store with a library that would silently ignore the key.';
}

/// The passphrase did not decrypt the store.
///
/// Indistinguishable, by design, from a corrupt file: a wrong key turns every
/// page into noise, and noise is not a database. We report the likely cause
/// rather than the literal one.
class WrongStorePassphrase implements Exception {
  const WrongStorePassphrase();

  @override
  String toString() => 'That passphrase does not open this store.';
}

/// Whether the file at [path] is an encrypted store.
///
/// A file that does not exist yet is not encrypted — there is nothing in it to
/// protect and the caller is about to create it.
Future<bool> storeIsEncrypted(String path) async {
  final file = File(path);
  if (!await file.exists()) return false;

  final handle = await file.open();
  try {
    final head = await handle.read(_plainTextHeader.length);
    return String.fromCharCodes(head) != _plainTextHeader;
  } finally {
    await handle.close();
  }
}

/// Throws [StoreCipherUnavailable] unless the loaded SQLite can encrypt.
///
/// Asked of an in-memory database so it can be answered before any real file is
/// touched, and so a build without the cipher fails on its own terms instead of
/// inside a half-open store.
Future<void> requireCipherSupport() async {
  final probe = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    await probe.rawQuery('SELECT sqlite3mc_version()');
  } catch (_) {
    throw const StoreCipherUnavailable();
  } finally {
    await probe.close();
  }
}

/// Opens the store at [path], applying [passphrase] if there is one.
///
/// `singleInstance: false` is deliberate and load-bearing. sqflite otherwise
/// caches open databases by path, and a *failed* open poisons that entry: after
/// one wrong passphrase the correct one fails too, for the life of the process.
/// Nobody would ever find that — it looks exactly like the right passphrase
/// having stopped working. The invariant the cache would otherwise provide
/// (never two handles on one file) is not lost: `ActiveClientController` owns
/// every client and no two live clients share a storage key.
///
/// Throws [WrongStorePassphrase] if the store does not open, and
/// [StoreCipherUnavailable] if this build cannot encrypt at all.
Future<Database> openStore({
  required String path,
  required String? passphrase,
}) async {
  if (passphrase != null) await requireCipherSupport();

  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      singleInstance: false,
      onConfigure: passphrase == null
          ? null
          : (db) => _applyKey(db, passphrase),
    ),
  );

  // The key is not checked when it is set, only when a page is read. Reading
  // the schema is the cheapest page there is, and doing it here means a wrong
  // passphrase surfaces as one exception from one place, rather than as a
  // "file is not a database" from wherever the SDK happened to look first.
  try {
    await database.rawQuery('SELECT count(*) FROM sqlite_master');
  } catch (_) {
    await database.close();
    throw const WrongStorePassphrase();
  }

  return database;
}

/// Changes what key an already-open store is encrypted with.
///
/// A [passphrase] of null decrypts it back to a plain SQLite file. The rewrite
/// happens in place, through the connection the caller is already using, so the
/// Matrix SDK holding this database keeps working across it — there is no close
/// and no rebuild, and therefore no window in which the app has no client.
///
/// What this cannot do is unwrite history. Encrypting a database that has been
/// on this disk in the clear protects it from here on; the pages it used to
/// occupy are not scrubbed, and a forensic read of the free space may still
/// find fragments of them. Full-disk encryption is what covers that, and the
/// security pane says so rather than letting the padlock imply otherwise.
Future<void> rekeyOpenStore(Database database, String? passphrase) async {
  if (passphrase != null) await requireCipherSupport();
  await database.rawQuery('PRAGMA rekey = ${_sqlLiteral(passphrase ?? '')}');
}

/// [rekeyOpenStore] for a store nobody has open.
///
/// Used for the accounts that are not the live one: they each own a separate
/// file, and every one of them has to move together with the passphrase or the
/// next account switch meets a store it cannot open.
Future<void> rekeyStoreAt({
  required String path,
  required String? from,
  required String? to,
}) async {
  final database = await openStore(path: path, passphrase: from);
  try {
    await rekeyOpenStore(database, to);
  } finally {
    await database.close();
  }
}

/// Applies the passphrase to a connection that has just been opened.
///
/// Order matters: the scheme has to be chosen before the key is derived, and
/// both have to happen before anything reads a page — which is why this belongs
/// in `onConfigure` and nowhere else.
Future<void> _applyKey(Database database, String passphrase) async {
  await database.rawQuery('PRAGMA cipher = ${_sqlLiteral(_cipherScheme)}');
  await database.rawQuery('PRAGMA key = ${_sqlLiteral(passphrase)}');
}

/// A SQL string literal.
///
/// `PRAGMA key` takes no bound parameters, so the passphrase is interpolated —
/// and a passphrase is exactly the kind of text that contains an apostrophe.
/// Doubling it is the SQL escape; skipping it would be a syntax error at best
/// and a silently truncated key at worst.
String _sqlLiteral(String value) => "'${value.replaceAll("'", "''")}'";

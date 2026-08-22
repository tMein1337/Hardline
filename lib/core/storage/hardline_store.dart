// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The Matrix SDK store, with the attachment cache moved inside the database.
///
/// The SDK's own `DatabaseFileStorage` writes every downloaded attachment,
/// avatar and thumbnail into a directory as an ordinary file — already
/// decrypted, since the point of the cache is to hold the plaintext. That is
/// fine as long as nothing on this machine is being protected, and it is the
/// hole that would otherwise sit next to an encrypted database: the message
/// saying "here is the photo" would be unreadable while the photo itself lay in
/// a folder for anyone to open.
///
/// So the cache goes where the rest of the account already is. One table, in
/// the same sqlite file, keyed by the same `PRAGMA key` as everything else.
/// Whatever protects the store protects the attachments, by construction rather
/// than by a second mechanism that has to be kept in step with the first — and
/// that stays true for whatever the storage layer becomes later.
///
/// It is unconditional. Doing this only while encryption is on would mean two
/// storage layouts, a migration in each direction, and a bug class where the
/// cache is in the place the other mode is looking. There is nothing to gain
/// from the directory when encryption is off, so there is no reason to keep it.
///
/// `MatrixSdkDatabase.buildWithoutOpen` exists for exactly this — the SDK
/// documents it as the way to extend the class — and every method overridden
/// here is declared on `DatabaseApi`, which is the type the SDK calls through.
class HardlineStore extends MatrixSdkDatabase {
  HardlineStore._(
    super.name, {
    required Database super.database,
    super.sqfliteFactory,
    super.maxFileSize,
  }) : super.buildWithoutOpen();

  /// Opens the SDK's boxes and makes sure the attachment table is there.
  ///
  /// Named after `MatrixSdkDatabase.init`, which it stands in for.
  static Future<HardlineStore> init({
    required String name,
    required Database connection,
    required DatabaseFactory factory,
    required int maxFileSize,
  }) async {
    final store = HardlineStore._(
      name,
      database: connection,
      sqfliteFactory: factory,
      maxFileSize: maxFileSize,
    );
    // Before `open()`, not after. `MatrixSdkDatabase.open` runs the SDK's own
    // schema migration when the stored version is behind, and that migration
    // ends in `clearCache()` — which this class overrides to also empty the
    // attachment table. A table that did not exist yet would take the launch
    // down with it, on the day some future SDK release bumps its version and
    // not a moment before.
    await store._createFileTable();
    await store.open();
    return store;
  }

  /// Not `files`: the SDK's boxes live in this same database under
  /// unprefixed names, and a collision would be discovered the day the SDK
  /// adds a box we happened to have picked. The prefix keeps the two sets of
  /// tables visibly ours and theirs.
  static const _table = 'hardline_files';

  /// The connection this store was opened on.
  ///
  /// Exposed so the security settings can re-key the database in place, through
  /// the handle the SDK is already using, without closing anything down. See
  /// `store_cipher.dart`.
  Database get connection => database!;

  /// True regardless of `fileStorageLocation`, which this class does not use.
  ///
  /// The SDK asks this before caching anything; leaving it to the mixin would
  /// answer "no" and turn every avatar into a fresh download.
  @override
  bool get supportsFileStoring => true;

  Future<void> _createFileTable() async {
    await connection.execute(
      'CREATE TABLE IF NOT EXISTS $_table ('
      'mxc TEXT PRIMARY KEY NOT NULL, '
      'bytes BLOB NOT NULL, '
      'saved_at INTEGER NOT NULL)',
    );
    // Expiry sweeps by age on every sync; without this they are a table scan
    // over the largest table in the database.
    await connection.execute(
      'CREATE INDEX IF NOT EXISTS ${_table}_saved_at ON $_table (saved_at)',
    );
  }

  @override
  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async {
    // `ConflictAlgorithm.replace` rather than the SDK's "skip if it already
    // exists": an mxc URI is content-addressed, so a second write is the same
    // bytes, and replacing refreshes `saved_at`. A file that keeps being looked
    // at therefore keeps being kept, which is what a cache is for.
    await connection.insert(_table, {
      'mxc': mxcUri.toString(),
      'bytes': bytes,
      'saved_at': time,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Uint8List?> getFile(Uri mxcUri) async {
    final rows = await connection.query(
      _table,
      columns: ['bytes'],
      where: 'mxc = ?',
      whereArgs: [mxcUri.toString()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List?;
  }

  @override
  Future<bool> deleteFile(Uri mxcUri) async {
    final removed = await connection.delete(
      _table,
      where: 'mxc = ?',
      whereArgs: [mxcUri.toString()],
    );
    return removed > 0;
  }

  /// Drops everything cached before [savedAt].
  ///
  /// The SDK passes a real cutoff timestamp here and its own implementation
  /// throws it away in favour of the file's modification time. We use the
  /// argument, which is both simpler and correct across a file being copied to
  /// another machine.
  ///
  /// The cutoff is the SDK's, not ours: `Client` sweeps on every sync with a
  /// fixed 30 day window, which is why this class carries no retention setting
  /// of its own to fall out of step with it.
  ///
  /// The file does not shrink when rows go — SQLite keeps the freed pages and
  /// reuses them. That is the same steady state a directory reaches, since both
  /// settle at about one retention window of attachments, so it is left alone
  /// rather than paid for with a VACUUM that rewrites the whole store.
  @override
  Future<void> deleteOldFiles(int savedAt) async {
    await connection.delete(
      _table,
      where: 'saved_at < ?',
      whereArgs: [savedAt],
    );
  }

  /// Signing out empties the store; the attachments are part of it.
  ///
  /// Without this the SDK's `clear()` would leave every cached photo behind,
  /// because `BoxCollection` only knows about the tables it created. That is
  /// exactly the leftover `deleteAccountStorage` exists to sweep up, and it
  /// should not need sweeping up.
  @override
  Future<void> clear() async {
    await super.clear();
    await connection.delete(_table);
  }

  /// A cache clear that left the largest cache in the database untouched would
  /// be a strange thing to offer.
  @override
  Future<void> clearCache() async {
    await super.clearCache();
    await connection.delete(_table);
  }
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Reports what is inside this machine's Matrix stores, without changing them.
///
/// ```
/// dart run tool/inspect_store.dart
/// ```
///
/// It answers the questions an encrypted store cannot be asked from outside:
/// whether the file is really encrypted, whether the attachment table exists,
/// and how much is in it. That is step 7 of TODO 5, and the reason it is worth
/// keeping rather than deleting once that passes — the list there is meant to
/// be re-run after anything touches `lib/core/storage/`, and without this the
/// only alternative is inferring from the file size.
///
/// It is also the only way for somebody to check the claim `PRIVACY.md` makes
/// on their own machine, rather than taking it on trust.
///
/// The passphrase is read from the terminal with echo off, used to open the
/// files **read-only**, and never written, logged or printed. Nothing else in
/// the repository reads it.
///
/// Windows only: the store location is hardcoded. Generalising it is a small
/// job, worth doing the day the Linux package can encrypt at all.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _plainTextHeader = 'SQLite format 3';

Future<void> main() async {
  sqfliteFfiInit();

  final appData = Platform.environment['APPDATA'];
  if (appData == null) {
    stderr.writeln('APPDATA is not set; this tool is Windows-only.');
    exitCode = 1;
    return;
  }

  final root = Directory(p.join(appData, 'Mein1337', 'Hardline', 'matrix'));
  if (!root.existsSync()) {
    stderr.writeln('No store directory at ${root.path}.');
    exitCode = 1;
    return;
  }

  final stores = root
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sqlite'))
      .toList();

  final legacyCaches = root
      .listSync()
      .whereType<Directory>()
      .where((d) => p.basename(d.path).startsWith('files'))
      .toList();

  stdout.writeln('Store directory: ${root.path}');
  stdout.writeln(
    'Old attachment directories: '
    '${legacyCaches.isEmpty ? 'none (expected)' : legacyCaches.map((d) => p.basename(d.path)).join(', ')}',
  );
  stdout.writeln('');

  final encrypted = <File>[];
  for (final store in stores) {
    final locked = _isEncrypted(store);
    stdout.writeln(
      '${p.basename(store.path).padRight(38)} '
      '${_kb(store.lengthSync()).padLeft(10)}  '
      '${locked ? 'encrypted' : 'PLAIN TEXT'}',
    );
    if (locked) encrypted.add(store);
  }
  stdout.writeln('');

  String? passphrase;
  if (encrypted.isNotEmpty) {
    passphrase = _readPassphrase(
      'Passphrase for the ${encrypted.length} encrypted '
      '${encrypted.length == 1 ? 'store' : 'stores'}: ',
    );
    if (passphrase.isEmpty) {
      stdout.writeln('Nothing typed; skipping the contents.');
      return;
    }
  }

  for (final store in stores) {
    stdout.writeln('');
    stdout.writeln(p.basename(store.path));
    await _report(store.path, _isEncrypted(store) ? passphrase : null);
  }
}

bool _isEncrypted(File file) {
  final handle = file.openSync();
  try {
    return String.fromCharCodes(handle.readSync(_plainTextHeader.length)) !=
        _plainTextHeader;
  } finally {
    handle.closeSync();
  }
}

Future<void> _report(String path, String? passphrase) async {
  Database database;
  try {
    database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        readOnly: true,
        singleInstance: false,
        onConfigure: passphrase == null
            ? null
            : (db) async {
                await db.rawQuery("PRAGMA cipher = 'chacha20'");
                await db.rawQuery(
                  "PRAGMA key = '${passphrase.replaceAll("'", "''")}'",
                );
              },
      ),
    );
    await database.rawQuery('SELECT count(*) FROM sqlite_master');
  } catch (_) {
    stdout.writeln('  could not be opened — wrong passphrase, or in use');
    return;
  }

  try {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'hardline_files'",
    );
    if (tables.isEmpty) {
      stdout.writeln('  hardline_files: MISSING — attachments are not cached');
      return;
    }

    final row = (await database.rawQuery(
      'SELECT count(*) AS n, coalesce(sum(length(bytes)), 0) AS b, '
      'min(saved_at) AS oldest, max(saved_at) AS newest FROM hardline_files',
    )).single;

    final count = row['n'] as int;
    stdout.writeln(
      '  hardline_files: $count '
      '${count == 1 ? 'attachment' : 'attachments'}, '
      '${_kb(row['b'] as int)}',
    );
    if (count > 0) {
      stdout.writeln('    oldest ${_when(row['oldest'] as int)}');
      stdout.writeln('    newest ${_when(row['newest'] as int)}');
    }
  } finally {
    await database.close();
  }
}

String _kb(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';

String _when(int millis) => DateTime.fromMillisecondsSinceEpoch(
  millis,
).toLocal().toString().split('.').first;

/// Reads a line without echoing it.
///
/// `echoMode` throws when stdin is not a terminal — piped input, or an IDE's
/// run console. Falling back to an echoing read is better than refusing, as
/// long as it says so first.
String _readPassphrase(String prompt) {
  stdout.write(prompt);
  var restored = false;
  try {
    stdin.echoMode = false;
    restored = true;
  } catch (_) {
    stdout.writeln('');
    stdout.write('(this terminal will show what you type) $prompt');
  }
  try {
    return stdin.readLineSync() ?? '';
  } on StdinException catch (error) {
    // No terminal attached at all: run this from a real console rather than
    // through a pipe or a tool that captures output.
    stdout.writeln('');
    stdout.writeln('Cannot read from this terminal ($error).');
    return '';
  } finally {
    if (restored) {
      try {
        stdin.echoMode = true;
      } catch (_) {
        // Nothing to put back if setting it never took.
      }
      stdout.writeln('');
    }
  }
}

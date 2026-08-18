// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Theme files on disk: the save/open dialogs and the read/write.
///
/// The counterpart to `attachment_picker_source.dart`, and split from
/// `theme_file.dart` for the same reason that file gives — everything that
/// touches a package or the filesystem in one place, so the format itself stays
/// a pure function over a string.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../features/chat/attachments/attachment_picker_source.dart';
import 'theme_entry.dart';
import 'theme_file.dart';

/// Writes [entry] to a file the user chooses. Returns the path, or null when
/// the dialog was cancelled — a cancel is not an error and should leave the
/// library untouched.
///
/// Reuses `chooseSaveLocation` rather than calling `getSaveLocation` again:
/// that helper already carries the Windows quirk about bare extensions, which
/// is the difference between saving "Midnight.theme.json" and saving
/// "Midnight" with no extension at all.
Future<String?> exportTheme(ThemeEntry entry) async {
  final path = await chooseSaveLocation(
    suggestedName: '${themeFileStem(entry.name)}$kThemeFileExtension',
  );
  if (path == null) return null;

  await File(path).writeAsString(encodeThemeFile(entry), flush: true);
  return path;
}

/// Reads a theme file the user picks. Null when the dialog was cancelled.
///
/// Throws [ThemeFileException] for a file that is not a readable theme, and a
/// `FileSystemException` if it cannot be read at all; the pane turns both into
/// one snack bar.
Future<ThemeEntry?> importTheme() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Theme', extensions: ['json']),
    ],
  );
  if (file == null) return null;

  final contents = await file.readAsString();
  return decodeThemeFile(
    contents,
    // `midnight.theme.json` → `midnight`: p.basenameWithoutExtension only
    // takes the last extension off, and a theme file has two.
    fallbackName: p
        .basenameWithoutExtension(file.name)
        .replaceAll(RegExp(r'\.theme$'), ''),
  );
}

/// Turns an import or export failure into something worth showing a user.
///
/// The counterpart to `describeAttachmentError`, and for the same reason: one
/// place where exceptions become text, so no widget has to invent its own
/// wording. [ThemeFileException] already carries a finished sentence; the rest
/// are the ways the disk says no.
String describeThemeFileError(Object error) {
  if (error is ThemeFileException) return error.message;
  if (error is PathAccessException) {
    return 'No permission to write there. Pick another folder.';
  }
  if (error is FileSystemException) {
    return 'Could not read that file. It may have been moved or deleted.';
  }
  return error.toString();
}

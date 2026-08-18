// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Reads and writes `.theme.json` files. The format is documented in the
/// README, under "Custom themes".
///
/// Pure: no `dart:io`, no dialogs, no providers — those live in
/// `theme_file_io.dart`. That split is what lets every rule below be tested by
/// handing a string to [decodeThemeFile], including the malformed cases that
/// are otherwise only reachable by hand-editing a file on disk.
library;

import 'dart:convert';

import 'color_slots.dart';
import 'hex_color.dart';
import 'theme_entry.dart';

/// Marks a file as ours. Checked on import, because JSON alone says nothing:
/// without it, any object with a `colors` key would silently become a theme.
const kThemeFileFormat = 'hardline.theme';

/// Format markers written by earlier builds, still accepted on import.
///
/// Exported themes live in people's file systems and outlive the name the app
/// was released under; refusing one because the project was renamed would throw
/// away work for no reason.
const kLegacyThemeFileFormats = {'matrix_client.theme'};

/// The format version this build writes and is the ceiling for reading.
const kThemeFileVersion = 1;

/// The extension an exported theme is suggested under.
///
/// Ends in `.json` deliberately: the file *is* JSON, and anyone who wants to
/// hand-edit one should get syntax highlighting for free.
const kThemeFileExtension = '.theme.json';

/// A theme file that cannot be read, with a message worth showing a user.
///
/// The counterpart to `describeAttachmentError` and `describeAuthError`: one
/// place where a malformed file becomes English, so no widget has to invent its
/// own wording for it.
class ThemeFileException implements Exception {
  const ThemeFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serialises [entry] as the contents of a `.theme.json` file.
///
/// Slots are written in [ColorSlot.all] order rather than map order so that
/// two exported themes diff line for line, and so a hand-editor finds the
/// surfaces grouped the way the palette file groups them.
String encodeThemeFile(ThemeEntry entry) {
  final colors = entry.toColors();

  return const JsonEncoder.withIndent('  ').convert({
    'format': kThemeFileFormat,
    'version': kThemeFileVersion,
    'name': entry.name,
    'colors': {
      for (final slot in ColorSlot.all) slot: hexOf(colors.slot(slot)),
    },
    'avatarPalette': [
      for (final color in colors.avatarPalette) hexOf(color),
    ],
  });
}

/// Parses the contents of a `.theme.json` file into an entry with a fresh id.
///
/// The id is generated rather than read: ids are local to an installation, and
/// a file carrying one would let an import silently overwrite a theme the user
/// already had. Importing the same file twice gives two entries, which is
/// visible and undoable.
///
/// Deliberately tolerant about *colours* and strict about *identity*. A file
/// that says it is a theme is read as far as it can be — unknown slots dropped,
/// missing ones filled from the default palette — because the alternative is
/// refusing a theme over a slot that was added to the app after it was written.
/// A file that does not say it is a theme is refused outright.
///
/// [fallbackName] is used when the file names no theme; callers pass the file's
/// own stem, which is what somebody renaming `midnight.theme.json` expects.
ThemeEntry decodeThemeFile(String contents, {String? fallbackName}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(contents);
  } on FormatException {
    throw const ThemeFileException(
      'That file is not valid JSON, so it cannot be read as a theme.',
    );
  }

  if (decoded is! Map) {
    throw const ThemeFileException(
      'That file does not contain a theme.',
    );
  }

  final format = decoded['format'];
  if (format != kThemeFileFormat && !kLegacyThemeFileFormats.contains(format)) {
    throw const ThemeFileException(
      'That is not a theme file. A theme exported from this app starts with '
      '"format": "$kThemeFileFormat".',
    );
  }

  final version = decoded['version'];
  if (version is! int) {
    throw const ThemeFileException(
      'That theme file does not say which format version it uses.',
    );
  }
  if (version > kThemeFileVersion) {
    throw ThemeFileException(
      'That theme was made by a newer version of this app (format $version, '
      'this build reads up to $kThemeFileVersion).',
    );
  }

  final rawColors = decoded['colors'];
  if (rawColors is! Map) {
    throw const ThemeFileException(
      'That theme file has no colours in it.',
    );
  }

  // Unparseable entries are skipped rather than fatal, and then filled in by
  // `completeColors` below — one mistyped line should cost that one colour,
  // not the whole theme.
  final colors = <String, int>{
    for (final entry in rawColors.entries)
      if (entry.key is String && entry.value is String)
        if (parseHexColor(entry.value as String) case final color?)
          entry.key as String: color.toARGB32(),
  };

  final rawRamp = decoded['avatarPalette'];
  final ramp = rawRamp is List
      ? [
          for (final value in rawRamp)
            if (value is String)
              if (parseHexColor(value) case final color?) color.toARGB32(),
        ]
      : const <int>[];

  final name = decoded['name'];

  return ThemeEntry(
    id: generateThemeId(),
    name: clampThemeName(
      name is String && name.trim().isNotEmpty
          ? name
          : (fallbackName ?? 'Imported theme'),
    ),
    colors: completeColors(colors),
    avatarPalette: ramp.isEmpty ? defaultAvatarPalette : ramp,
  );
}

/// A filename for [name], without the extension.
///
/// Strips what Windows refuses in a path plus anything else awkward to type,
/// and falls back to a fixed stem when a name is entirely punctuation — a save
/// dialog opening on an empty filename looks broken.
String themeFileStem(String name) {
  final cleaned = name
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? 'theme' : cleaned;
}

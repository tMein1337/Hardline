// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/theme/app_theme_state.dart';
import 'package:hardline/theme/color_slots.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_entry.dart';
import 'package:hardline/theme/theme_file.dart';

/// The rename of the theme layer changed three slot names, the three built-in
/// preset ids and the theme file's format marker. All three are things users
/// already have on disk, so each one gets carried forward rather than reset.
void main() {
  group('slot names', () {
    test('a stored patch under the old names is carried forward', () {
      final migrated = migrateSlotNames({
        'serverRail': 0xFF111111,
        'channelSidebar': 0xFF222222,
        'chatBackground': 0xFF333333,
        'accent': 0xFF444444,
      });

      expect(migrated, {
        ColorSlot.spaceRail: 0xFF111111,
        ColorSlot.roomSidebar: 0xFF222222,
        ColorSlot.timelineBackground: 0xFF333333,
        ColorSlot.accent: 0xFF444444,
      });
    });

    test('a map with nothing to migrate is returned unchanged', () {
      const input = {'accent': 0xFF444444};
      expect(identical(migrateSlotNames(input), input), isTrue);
    });

    // A file could carry both spellings — hand-edited, or written by a build
    // mid-rename. The current name is the one the user last saw in the editor.
    test('a value under the current name wins over the old one', () {
      final migrated = migrateSlotNames({
        'serverRail': 0xFF111111,
        'spaceRail': 0xFF999999,
      });

      expect(migrated[ColorSlot.spaceRail], 0xFF999999);
    });

    test('completeColors fills from the default palette after migrating', () {
      final completed = completeColors({'serverRail': 0xFF111111});

      expect(completed[ColorSlot.spaceRail], 0xFF111111);
      expect(
        completed[ColorSlot.accent],
        AppPalettes.dark.accent.toARGB32(),
      );
      expect(completed.keys.toSet(), ColorSlot.all.toSet());
    });
  });

  group('preset ids', () {
    test('each built-in id maps to its replacement', () {
      expect(migratePresetId('discord_dark'), 'hardline_dark');
      expect(migratePresetId('discord_dark_classic'), 'hardline_night');
      expect(migratePresetId('discord_light'), 'hardline_day');
    });

    test('an unknown id is left alone', () {
      expect(migratePresetId('theme_abc123'), 'theme_abc123');
    });

    test('a saved selection still names a theme that exists', () {
      final state = AppThemeState.fromJson(
        jsonDecode('{"presetId":"discord_light"}') as Map<String, dynamic>,
      );

      expect(state.presetId, 'hardline_day');
      expect(AppPalettes.byIdMap.containsKey(state.presetId), isTrue);
    });

    test('a stored library entry is renamed with it', () {
      final entry = ThemeEntry.fromJson({
        'id': 'discord_dark',
        'name': 'Dark',
        'colors': <String, int>{},
        'avatarPalette': <int>[],
      });

      expect(entry!.id, 'hardline_dark');
      // Still a built-in, so its slots stay revertible.
      expect(entry.isSeeded, isTrue);
    });

    test('the legacy override patch is migrated with the selection', () {
      final state = AppThemeState.fromJson(
        jsonDecode('{"presetId":"discord_dark","overrides":{'
                '"serverRail":4278190080}}')
            as Map<String, dynamic>,
      );

      expect(state.overrides, {ColorSlot.spaceRail: 4278190080});
      expect(state.resolve().spaceRail, const Color(0xFF000000));
    });
  });

  group('theme files', () {
    test('a file exported by an earlier build still imports', () {
      final entry = decodeThemeFile(
        jsonEncode({
          'format': 'matrix_client.theme',
          'version': 1,
          'name': 'Saved earlier',
          'colors': {'serverRail': '#112233'},
        }),
      );

      expect(entry.name, 'Saved earlier');
      expect(entry.colors[ColorSlot.spaceRail], 0xFF112233);
    });

    test('a file this build writes carries the current marker', () {
      final encoded = jsonDecode(
        encodeThemeFile(
          ThemeEntry.fromColors(
            id: 'hardline_dark',
            name: 'Flight Deck',
            colors: AppPalettes.dark,
          ),
        ),
      ) as Map<String, Object?>;

      expect(encoded['format'], 'hardline.theme');
      expect(encoded['format'], isNot('matrix_client.theme'));
    });

    test('something that is not a theme is still refused', () {
      expect(
        () => decodeThemeFile('{"format":"something.else","version":1}'),
        throwsA(isA<ThemeFileException>()),
      );
    });
  });
}

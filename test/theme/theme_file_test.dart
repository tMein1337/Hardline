// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/theme/color_slots.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_entry.dart';
import 'package:hardline/theme/theme_file.dart';

/// A theme file body, so each test can name only the part it is about.
String fileWith({
  Object? format = kThemeFileFormat,
  Object? version = kThemeFileVersion,
  Object? name = 'Midnight',
  Map<String, Object?>? colors,
  Object? avatarPalette,
}) => jsonEncode({
  // Null omits the key entirely, which is how a test says "this file does not
  // declare a version" rather than "declares it as null".
  'format': ?format,
  'version': ?version,
  'name': ?name,
  'colors': colors ?? {ColorSlot.accent: '#FF00FF00'},
  'avatarPalette': ?avatarPalette,
});

void main() {
  final dark = AppPalettes.dark;

  group('encodeThemeFile', () {
    final entry = ThemeEntry.fromColors(
      id: 'hardline_dark',
      name: 'Midnight',
      colors: dark,
    );

    test('writes every slot, in ColorSlot.all order', () {
      final json = jsonDecode(encodeThemeFile(entry)) as Map<String, Object?>;
      final colors = json['colors']! as Map<String, Object?>;

      // Order matters: it is what makes two exported themes diff line for line.
      expect(colors.keys, ColorSlot.all);
    });

    test('declares the format and version', () {
      final json = jsonDecode(encodeThemeFile(entry)) as Map<String, Object?>;

      expect(json['format'], kThemeFileFormat);
      expect(json['version'], kThemeFileVersion);
      expect(json['name'], 'Midnight');
    });

    // Alpha is not decoration: `scrim` and `dropOverlay` are washes, and an
    // exported theme that dropped their alpha would import as solid blocks.
    test('keeps alpha on translucent slots', () {
      final json = jsonDecode(encodeThemeFile(entry)) as Map<String, Object?>;
      final colors = json['colors']! as Map<String, Object?>;

      expect(colors[ColorSlot.scrim], '#CC000000');
      expect(colors[ColorSlot.voiceParticipantRow], '#00000000');
    });

    test('round-trips a theme unchanged', () {
      final decoded = decodeThemeFile(encodeThemeFile(entry));

      expect(decoded.name, entry.name);
      expect(decoded.colors, entry.colors);
      expect(decoded.avatarPalette, entry.avatarPalette);
      expect(decoded.toColors(), dark);
    });

    test('the id is local and is not carried by the file', () {
      final decoded = decodeThemeFile(encodeThemeFile(entry));

      // Importing must never be able to overwrite a theme already in the
      // library, so a fresh id is minted rather than read.
      expect(decoded.id, isNot(entry.id));
      expect(jsonDecode(encodeThemeFile(entry)), isNot(contains('id')));
    });
  });

  group('decodeThemeFile', () {
    test('accepts #RRGGBB and assumes opaque', () {
      final entry = decodeThemeFile(
        fileWith(colors: {ColorSlot.accent: '#00FF00'}),
      );

      expect(entry.toColors().accent, const Color(0xFF00FF00));
    });

    test('fills a missing slot from the default palette', () {
      final entry = decodeThemeFile(
        fileWith(colors: {ColorSlot.accent: '#FF00FF00'}),
      );

      // Completeness is the point: a partial file must still yield a theme
      // that renders, rather than sixty magenta slots.
      expect(entry.colors.keys.toSet(), ColorSlot.all.toSet());
      expect(entry.toColors().timelineBackground, dark.timelineBackground);
    });

    test('ignores a slot this build has never heard of', () {
      final entry = decodeThemeFile(
        fileWith(
          colors: {ColorSlot.accent: '#FF00FF00', 'slotFromTheFuture': '#FFF'},
        ),
      );

      expect(entry.colors.containsKey('slotFromTheFuture'), isFalse);
      expect(entry.colors.keys.toSet(), ColorSlot.all.toSet());
    });

    test('a single unparseable colour costs only that colour', () {
      final entry = decodeThemeFile(
        fileWith(
          colors: {
            ColorSlot.accent: 'not a colour',
            ColorSlot.danger: '#FF00FF00',
          },
        ),
      );

      expect(entry.toColors().accent, dark.accent);
      expect(entry.toColors().danger, const Color(0xFF00FF00));
    });

    test('falls back to the built-in avatar ramp when there is none', () {
      final entry = decodeThemeFile(fileWith());

      expect(entry.avatarPalette, defaultAvatarPalette);
    });

    test('reads an avatar ramp when the file has one', () {
      final entry = decodeThemeFile(
        fileWith(avatarPalette: ['#FF112233', '#FF445566']),
      );

      expect(entry.avatarPalette, [0xFF112233, 0xFF445566]);
    });

    test('names the theme after the file when the file does not', () {
      final entry = decodeThemeFile(
        fileWith(name: null),
        fallbackName: 'midnight',
      );

      expect(entry.name, 'midnight');
    });

    test('trims and caps an absurd name', () {
      final entry = decodeThemeFile(fileWith(name: '  ${'a' * 200}  '));

      expect(entry.name.length, kMaxThemeNameLength);
    });

    test('rejects a file that is not JSON', () {
      expect(
        () => decodeThemeFile('not json at all'),
        throwsA(isA<ThemeFileException>()),
      );
    });

    test('rejects JSON that is not ours', () {
      expect(
        () => decodeThemeFile(jsonEncode({'colors': {}})),
        throwsA(isA<ThemeFileException>()),
      );
      expect(
        () => decodeThemeFile(fileWith(format: 'some.other.thing')),
        throwsA(isA<ThemeFileException>()),
      );
    });

    test('rejects a format version it cannot read', () {
      expect(
        () => decodeThemeFile(fileWith(version: kThemeFileVersion + 1)),
        throwsA(isA<ThemeFileException>()),
      );
      expect(
        () => decodeThemeFile(fileWith(version: null)),
        throwsA(isA<ThemeFileException>()),
      );
    });

    test('rejects a theme with no colours object', () {
      expect(
        () => decodeThemeFile(
          jsonEncode({
            'format': kThemeFileFormat,
            'version': kThemeFileVersion,
            'name': 'Midnight',
          }),
        ),
        throwsA(isA<ThemeFileException>()),
      );
    });

    test('every message is a sentence, not a stack trace', () {
      try {
        decodeThemeFile('{');
        fail('should have thrown');
      } on ThemeFileException catch (error) {
        expect(error.message, endsWith('.'));
        expect(error.message, isNot(contains('Exception')));
      }
    });
  });

  group('themeFileStem', () {
    test('strips what a path cannot contain', () {
      expect(themeFileStem('Mid/night: "one"?'), 'Midnight one');
    });

    test('falls back rather than producing an empty filename', () {
      expect(themeFileStem('//::'), 'theme');
      expect(themeFileStem('   '), 'theme');
    });
  });
}

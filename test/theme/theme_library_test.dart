// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/core/providers/injected_providers.dart';
import 'package:hardline/theme/color_slots.dart';
import 'package:hardline/theme/palettes.dart';
import 'package:hardline/theme/theme_entry.dart';
import 'package:hardline/theme/theme_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  /// A container whose preferences start as [stored], so the seeding and
  /// recovery paths in `build()` can each be reached.
  Future<void> open([Map<String, Object> stored = const {}]) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
  }

  ThemeLibraryState read() => container.read(themeLibraryProvider);
  ThemeLibrary notifier() => container.read(themeLibraryProvider.notifier);

  tearDown(() => container.dispose());

  group('seeding', () {
    test('a fresh install starts with the three built-in themes', () async {
      await open();

      expect(read().entries.map((e) => e.id), AppPalettes.byIdMap.keys);
      expect(
        read().entries.map((e) => e.name),
        AppPalettes.labels.values,
      );
    });

    // The ids are the ones `presetId` already held, so an installation that
    // upgrades keeps the theme it had selected without a migration step.
    test('seeded themes keep the ids the app already persisted', () async {
      await open();

      expect(read().byId(AppPalettes.defaultId), isNotNull);
      expect(read().byId(AppPalettes.defaultId)!.isSeeded, isTrue);
    });

    test('a seeded theme carries every slot', () async {
      await open();
      final entry = read().byId('hardline_day')!;

      expect(entry.colors.keys.toSet(), ColorSlot.all.toSet());
      expect(entry.toColors(), AppPalettes.day);
    });

    test('a corrupt stored library degrades to the seeded three', () async {
      await open({'theme_library_v1': 'not json'});

      expect(read().entries.length, 3);
    });

    // An empty list is as unusable as a corrupt one: nothing to select, edit,
    // or duplicate from.
    test('an empty stored library is re-seeded', () async {
      await open({
        'theme_library_v1': jsonEncode({'version': 1, 'entries': <Object>[]}),
      });

      expect(read().entries.length, 3);
    });

    test('a stored library is used as-is', () async {
      await open();
      final id = notifier().duplicate('hardline_dark');
      final stored = container.read(prefsProvider).getString('theme_library_v1');

      await open({'theme_library_v1': stored!});

      expect(read().entries.length, 4);
      expect(read().byId(id), isNotNull);
    });
  });

  group('duplicate', () {
    test('copies every colour and the avatar ramp verbatim', () async {
      await open();
      final source = read().byId('hardline_dark')!;
      final id = notifier().duplicate('hardline_dark');
      final copy = read().byId(id)!;

      expect(copy.colors, source.colors);
      expect(copy.avatarPalette, source.avatarPalette);
      // The point of the feature: applying the copy is indistinguishable from
      // applying the original.
      expect(copy.toColors(), source.toColors());
    });

    test('the copy is its own theme, not a built-in', () async {
      await open();
      final id = notifier().duplicate('hardline_dark');
      final copy = read().byId(id)!;

      expect(copy.id, isNot('hardline_dark'));
      // False even though it was copied from Dark: the original stays
      // revertible and restorable, the copy is freely editable.
      expect(copy.isSeeded, isFalse);
    });

    test('lands directly below its source', () async {
      await open();
      final id = notifier().duplicate('hardline_dark');

      expect(read().indexOf(id), read().indexOf('hardline_dark') + 1);
    });

    test('names disambiguate rather than collide', () async {
      await open();
      final first = notifier().duplicate('hardline_dark');
      final second = notifier().duplicate('hardline_dark');

      expect(read().byId(first)!.name, 'Flight Deck (copy)');
      expect(read().byId(second)!.name, 'Flight Deck (copy) (2)');
    });

    // The failure this guards against is invisible until somebody duplicates a
    // theme and watches both of them change together.
    test('editing the copy leaves the source untouched', () async {
      await open();
      final id = notifier().duplicate('hardline_dark');
      await notifier().setSlot(id, ColorSlot.accent, const Color(0xFF00FF00));

      expect(read().byId(id)!.toColors().accent, const Color(0xFF00FF00));
      expect(
        read().byId('hardline_dark')!.toColors().accent,
        AppPalettes.dark.accent,
      );
    });

    test('duplicating a copy works, and is independent again', () async {
      await open();
      final first = notifier().duplicate('hardline_dark');
      await notifier().setSlot(
        first,
        ColorSlot.accent,
        const Color(0xFF00FF00),
      );
      final second = notifier().duplicate(first);

      expect(read().byId(second)!.toColors().accent, const Color(0xFF00FF00));

      await notifier().setSlot(
        second,
        ColorSlot.accent,
        const Color(0xFF0000FF),
      );
      expect(read().byId(first)!.toColors().accent, const Color(0xFF00FF00));
    });

    test('an unknown id is a no-op', () async {
      await open();
      final before = read().entries.length;

      expect(notifier().duplicate('nope'), 'nope');
      expect(read().entries.length, before);
    });
  });

  group('editing', () {
    test('setSlot changes only the named slot of the named theme', () async {
      await open();
      await notifier().setSlot(
        'hardline_dark',
        ColorSlot.accent,
        const Color(0xFF00FF00),
      );

      final entry = read().byId('hardline_dark')!;
      expect(entry.toColors().accent, const Color(0xFF00FF00));
      expect(entry.toColors().timelineBackground, AppPalettes.dark.timelineBackground);
      expect(
        read().byId('hardline_day')!.toColors().accent,
        AppPalettes.day.accent,
      );
    });

    // A theme jumping to the bottom of the list because a colour changed would
    // make the list unusable while editing.
    test('editing does not reorder the list', () async {
      await open();
      await notifier().setSlot(
        'hardline_dark',
        ColorSlot.accent,
        const Color(0xFF00FF00),
      );

      expect(read().indexOf('hardline_dark'), 0);
    });

    test('a dragged slider does not write until it is released', () async {
      await open();
      await notifier().setSlot(
        'hardline_dark',
        ColorSlot.accent,
        const Color(0xFF00FF00),
        commit: false,
      );

      // State moves so the app repaints under the pointer...
      expect(
        read().byId('hardline_dark')!.toColors().accent,
        const Color(0xFF00FF00),
      );
      // ...but nothing has been persisted yet.
      expect(
        container.read(prefsProvider).getString('theme_library_v1'),
        isNull,
      );
    });

    test('revertSlot puts a built-in slot back', () async {
      await open();
      await notifier().setSlot(
        'hardline_dark',
        ColorSlot.accent,
        const Color(0xFF00FF00),
      );
      await notifier().revertSlot('hardline_dark', ColorSlot.accent);

      expect(
        read().byId('hardline_dark')!.toColors().accent,
        AppPalettes.dark.accent,
      );
    });

    test('revertSlot is a no-op on a theme of the user’s own', () async {
      await open();
      final id = notifier().duplicate('hardline_dark');
      await notifier().setSlot(id, ColorSlot.accent, const Color(0xFF00FF00));
      await notifier().revertSlot(id, ColorSlot.accent);

      // Nothing to go back to, so the colour stays as the user set it rather
      // than snapping to a palette they never chose.
      expect(read().byId(id)!.toColors().accent, const Color(0xFF00FF00));
    });

    test('renaming disambiguates against the existing names', () async {
      await open();
      await notifier().rename('hardline_day', 'Flight Deck');

      expect(read().byId('hardline_day')!.name, 'Flight Deck (2)');
    });

    // A theme does not clash with itself. Without this, confirming the rename
    // dialog without editing it — or the New theme dialog, which offers
    // "X (copy)" as its initial value — bumps the number every time.
    test('renaming a theme to the name it already has changes nothing', () async {
      await open();
      await notifier().rename('hardline_dark', 'Flight Deck');

      expect(read().byId('hardline_dark')!.name, 'Flight Deck');
    });

    test('creating a theme under the name duplicate already gave it', () async {
      await open();
      final id = notifier().duplicate('hardline_dark');
      await notifier().rename(id, 'Flight Deck (copy)');

      expect(read().byId(id)!.name, 'Flight Deck (copy)');
    });
  });

  group('remove and restore', () {
    test('removes the named theme and leaves the rest', () async {
      await open();
      await notifier().remove('hardline_day');

      expect(read().byId('hardline_day'), isNull);
      expect(read().entries.length, 2);
    });

    // The backstop for the pane disabling the action: with nothing in the
    // library there is no theme to select and no way back.
    test('the last theme cannot be removed', () async {
      await open();
      await notifier().remove('hardline_day');
      await notifier().remove('hardline_night');
      await notifier().remove('hardline_dark');

      expect(read().entries.length, 1);
    });

    test('restoreBuiltIns puts back only what is missing', () async {
      await open();
      await notifier().remove('hardline_day');
      await notifier().setSlot(
        'hardline_dark',
        ColorSlot.accent,
        const Color(0xFF00FF00),
      );
      await notifier().restoreBuiltIns();

      expect(read().byId('hardline_day')!.toColors(), AppPalettes.day);
      // It restores what is gone rather than resetting everything — edits to a
      // built-in that is still present survive.
      expect(
        read().byId('hardline_dark')!.toColors().accent,
        const Color(0xFF00FF00),
      );
    });

    test('restoreBuiltIns is a no-op when all three are present', () async {
      await open();
      final before = read();
      await notifier().restoreBuiltIns();

      expect(read(), before);
    });

    test('missingSeededIds reports in the built-in order', () async {
      await open();
      await notifier().remove('hardline_day');
      await notifier().remove('hardline_dark');

      expect(read().missingSeededIds, ['hardline_dark', 'hardline_day']);
    });
  });

  group('add', () {
    test('appends and returns the stored id', () async {
      await open();
      final entry = ThemeEntry.fromColors(
        id: generateThemeId(),
        name: 'Imported',
        colors: AppPalettes.day,
      );
      final id = notifier().add(entry);

      expect(id, entry.id);
      expect(read().entries.last.id, id);
    });

    test('importing the same theme twice gives two rows, named apart', () async {
      await open();
      ThemeEntry incoming() => ThemeEntry.fromColors(
        id: generateThemeId(),
        name: 'Midnight',
        colors: AppPalettes.day,
      );

      final first = notifier().add(incoming());
      final second = notifier().add(incoming());

      expect(read().byId(first)!.name, 'Midnight');
      expect(read().byId(second)!.name, 'Midnight (2)');
    });
  });

  group('ThemeEntry', () {
    test('round-trips through JSON', () async {
      final entry = ThemeEntry.fromColors(
        id: 'x',
        name: 'Midnight',
        colors: AppPalettes.day,
      );

      expect(ThemeEntry.fromJson(entry.toJson()), entry);
    });

    test('a stored entry missing a slot is completed, not dropped', () {
      // What a theme saved before a slot was added to the app looks like.
      final entry = ThemeEntry.fromJson({
        'id': 'x',
        'name': 'Midnight',
        'colors': {ColorSlot.accent: 0xFF00FF00},
        'avatarPalette': <int>[],
      })!;

      expect(entry.colors.keys.toSet(), ColorSlot.all.toSet());
      expect(entry.toColors().accent, const Color(0xFF00FF00));
      expect(entry.toColors().timelineBackground, AppPalettes.dark.timelineBackground);
      expect(entry.avatarPalette, defaultAvatarPalette);
    });

    test('an unusable entry is null rather than fatal', () {
      expect(ThemeEntry.fromJson('not a map'), isNull);
      expect(ThemeEntry.fromJson({'id': '', 'name': 'x', 'colors': {}}), isNull);
      expect(ThemeEntry.fromJson({'id': 'x', 'name': '  ', 'colors': {}}), isNull);
      expect(ThemeEntry.fromJson({'id': 'x', 'name': 'y'}), isNull);
    });

    test('one bad entry drops out without taking the list down', () {
      final state = ThemeLibraryState.fromJson({
        'entries': [
          {'id': 'good', 'name': 'Good', 'colors': <String, int>{}},
          'rubbish',
          {'id': '', 'name': 'Nameless', 'colors': <String, int>{}},
        ],
      });

      expect(state.entries.map((e) => e.id), ['good']);
    });

    test('copyAs shares no mutable structure with its source', () {
      final source = ThemeEntry.fromColors(
        id: 'a',
        name: 'A',
        colors: AppPalettes.dark,
      );
      final copy = source.copyAs(id: 'b', name: 'B');

      expect(identical(copy.colors, source.colors), isFalse);
      expect(identical(copy.avatarPalette, source.avatarPalette), isFalse);
      expect(copy.colors, source.colors);
    });
  });
}

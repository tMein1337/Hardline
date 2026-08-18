// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hardline/theme/app_theme_state.dart';
import 'package:hardline/theme/color_slots.dart';
import 'package:hardline/theme/palettes.dart';

void main() {
  group('palettes', () {
    // The map-based design means a palette can omit a slot and still compile.
    // That renders as magenta at runtime, which is exactly the kind of bug
    // that survives review, so it is asserted here instead.
    for (final entry in AppPalettes.byIdMap.entries) {
      test('"${entry.key}" defines every slot exactly once', () {
        expect(
          entry.value.slots.keys.toSet(),
          ColorSlot.all.toSet(),
          reason: 'palette slots must match ColorSlot.all',
        );
        expect(entry.value.avatarPalette, isNotEmpty);
      });
    }

    test('every preset id has a display label', () {
      expect(
        AppPalettes.labels.keys.toSet(),
        AppPalettes.byIdMap.keys.toSet(),
      );
    });

    test('default id resolves to a real palette', () {
      expect(
        AppPalettes.byIdMap.containsKey(AppPalettes.defaultId),
        isTrue,
      );
    });

    test('unknown id falls back to dark rather than throwing', () {
      expect(AppPalettes.byId('nope'), AppPalettes.dark);
    });

    test('dark palettes report isDark, light does not', () {
      expect(AppPalettes.dark.isDark, isTrue);
      expect(AppPalettes.night.isDark, isTrue);
      expect(AppPalettes.day.isDark, isFalse);
    });
  });

  group('AppPalette', () {
    test('copyWith merges slots rather than replacing them', () {
      const red = Color(0xFFFF0000);
      final patched = AppPalettes.dark.copyWith(
        slots: {ColorSlot.accent: red},
      );

      expect(patched.accent, red);
      // Every other slot must survive the merge.
      expect(patched.spaceRail, AppPalettes.dark.spaceRail);
      expect(patched.slots.length, AppPalettes.dark.slots.length);
    });

    test('lerp returns the endpoints at t=0 and t=1', () {
      const a = AppPalettes.dark;
      const b = AppPalettes.day;

      expect(a.lerp(b, 0), a);
      expect(a.lerp(b, 1), b);
    });

    test('lerp with a null other is a no-op', () {
      expect(AppPalettes.dark.lerp(null, 0.5), AppPalettes.dark);
    });

    test('equality is by value, not identity', () {
      final copy = AppPalettes.dark.copyWith();
      expect(copy, AppPalettes.dark);
      expect(copy.hashCode, AppPalettes.dark.hashCode);
    });

    test('applyOverrides ignores unknown slot names', () {
      final result = AppPalettes.dark.applyOverrides({
        'notARealSlot': 0xFF00FF00,
      });
      expect(result, AppPalettes.dark);
    });

    test('applyOverrides changes only the named slots', () {
      const green = Color(0xFF00FF00);
      final result = AppPalettes.dark.applyOverrides({
        ColorSlot.accent: green.toARGB32(),
      });

      expect(result.accent, green);
      expect(result.timelineBackground, AppPalettes.dark.timelineBackground);
    });

    test('diffFrom reports only what actually differs', () {
      const green = Color(0xFF00FF00);
      final patched = AppPalettes.dark.copyWith(
        slots: {ColorSlot.accent: green},
      );

      expect(patched.diffFrom(AppPalettes.dark), {
        ColorSlot.accent: green.toARGB32(),
      });
      expect(AppPalettes.dark.diffFrom(AppPalettes.dark), isEmpty);
    });

    test('avatarColorFor is stable for the same seed', () {
      final first = AppPalettes.dark.avatarColorFor('@alice:example.org');
      final second = AppPalettes.dark.avatarColorFor('@alice:example.org');
      expect(first, second);
      expect(AppPalettes.dark.avatarPalette, contains(first));
    });
  });

  group('AppThemeState', () {
    test('round-trips through JSON', () {
      const state = AppThemeState(
        presetId: 'hardline_day',
        overrides: {ColorSlot.accent: 0xFF00FF00},
        tooltipDelay: Duration(milliseconds: 850),
      );

      expect(AppThemeState.fromJson(state.toJson()), state);
    });

    test('resolve applies overrides on top of the preset', () {
      const state = AppThemeState(
        presetId: 'hardline_day',
        overrides: {ColorSlot.accent: 0xFF00FF00},
      );

      final colors = state.resolve();
      expect(colors.accent, const Color(0xFF00FF00));
      expect(colors.timelineBackground, AppPalettes.day.timelineBackground);
    });

    test('malformed JSON degrades to defaults instead of throwing', () {
      final state = AppThemeState.fromJson({
        'presetId': 42,
        'overrides': 'not a map',
        'tooltipDelayMs': 'soon',
      });

      expect(state.presetId, AppPalettes.defaultId);
      expect(state.overrides, isEmpty);
      expect(state.tooltipDelay, kDefaultTooltipDelay);
    });

    test('a blob written before tooltips existed still loads', () {
      final state = AppThemeState.fromJson({
        'presetId': 'hardline_day',
        'overrides': <String, int>{},
      });

      expect(state.tooltipDelay, kDefaultTooltipDelay);
    });

    // Clamped at parse time so a hand-edited value cannot produce tooltips that
    // never appear, which is indistinguishable from tooltips being broken.
    test('an absurd stored delay is clamped rather than obeyed', () {
      final state = AppThemeState.fromJson({'tooltipDelayMs': 600000});
      expect(state.tooltipDelay, kMaxTooltipDelay);

      final negative = AppThemeState.fromJson({'tooltipDelayMs': -5});
      expect(negative.tooltipDelay, Duration.zero);
    });

    // How the app actually resolves: the palette comes from the library, not
    // from the `const` map, so a theme the user built is reachable by an id
    // `AppPalettes` has never heard of.
    test('resolve prefers the base it is given over the preset id', () {
      const state = AppThemeState(presetId: 'hardline_day');
      final base = AppPalettes.dark.copyWith(
        slots: {ColorSlot.accent: const Color(0xFF00FF00)},
      );

      final colors = state.resolve(base: base);
      expect(colors.accent, const Color(0xFF00FF00));
      expect(colors.timelineBackground, AppPalettes.dark.timelineBackground);
    });

    test('a legacy override still applies on top of a library theme', () {
      const state = AppThemeState(
        presetId: 'a_theme_the_user_made',
        overrides: {ColorSlot.accent: 0xFF00FF00},
      );

      final colors = state.resolve(base: AppPalettes.day);
      expect(colors.accent, const Color(0xFF00FF00));
      expect(colors.timelineBackground, AppPalettes.day.timelineBackground);
    });

    test('overrides survive a preset change', () {
      const state = AppThemeState(
        overrides: {ColorSlot.accent: 0xFF00FF00},
      );
      final switched = state.copyWith(presetId: 'hardline_day');

      expect(switched.resolve().accent, const Color(0xFF00FF00));
    });
  });
}

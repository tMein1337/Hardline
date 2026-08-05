import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_client/theme/app_theme_state.dart';
import 'package:matrix_client/theme/discord_colors.dart';
import 'package:matrix_client/theme/discord_palettes.dart';

void main() {
  group('palettes', () {
    // The map-based design means a palette can omit a slot and still compile.
    // That renders as magenta at runtime, which is exactly the kind of bug
    // that survives review, so it is asserted here instead.
    for (final entry in DiscordPalettes.byIdMap.entries) {
      test('"${entry.key}" defines every slot exactly once', () {
        expect(
          entry.value.slots.keys.toSet(),
          DiscordSlot.all.toSet(),
          reason: 'palette slots must match DiscordSlot.all',
        );
        expect(entry.value.avatarPalette, isNotEmpty);
      });
    }

    test('every preset id has a display label', () {
      expect(
        DiscordPalettes.labels.keys.toSet(),
        DiscordPalettes.byIdMap.keys.toSet(),
      );
    });

    test('default id resolves to a real palette', () {
      expect(
        DiscordPalettes.byIdMap.containsKey(DiscordPalettes.defaultId),
        isTrue,
      );
    });

    test('unknown id falls back to dark rather than throwing', () {
      expect(DiscordPalettes.byId('nope'), DiscordPalettes.dark);
    });

    test('dark palettes report isDark, light does not', () {
      expect(DiscordPalettes.dark.isDark, isTrue);
      expect(DiscordPalettes.darkClassic.isDark, isTrue);
      expect(DiscordPalettes.light.isDark, isFalse);
    });
  });

  group('DiscordColors', () {
    test('copyWith merges slots rather than replacing them', () {
      const red = Color(0xFFFF0000);
      final patched = DiscordPalettes.dark.copyWith(
        slots: {DiscordSlot.accent: red},
      );

      expect(patched.accent, red);
      // Every other slot must survive the merge.
      expect(patched.serverRail, DiscordPalettes.dark.serverRail);
      expect(patched.slots.length, DiscordPalettes.dark.slots.length);
    });

    test('lerp returns the endpoints at t=0 and t=1', () {
      const a = DiscordPalettes.dark;
      const b = DiscordPalettes.light;

      expect(a.lerp(b, 0), a);
      expect(a.lerp(b, 1), b);
    });

    test('lerp with a null other is a no-op', () {
      expect(DiscordPalettes.dark.lerp(null, 0.5), DiscordPalettes.dark);
    });

    test('equality is by value, not identity', () {
      final copy = DiscordPalettes.dark.copyWith();
      expect(copy, DiscordPalettes.dark);
      expect(copy.hashCode, DiscordPalettes.dark.hashCode);
    });

    test('applyOverrides ignores unknown slot names', () {
      final result = DiscordPalettes.dark.applyOverrides({
        'notARealSlot': 0xFF00FF00,
      });
      expect(result, DiscordPalettes.dark);
    });

    test('applyOverrides changes only the named slots', () {
      const green = Color(0xFF00FF00);
      final result = DiscordPalettes.dark.applyOverrides({
        DiscordSlot.accent: green.toARGB32(),
      });

      expect(result.accent, green);
      expect(result.chatBackground, DiscordPalettes.dark.chatBackground);
    });

    test('diffFrom reports only what actually differs', () {
      const green = Color(0xFF00FF00);
      final patched = DiscordPalettes.dark.copyWith(
        slots: {DiscordSlot.accent: green},
      );

      expect(patched.diffFrom(DiscordPalettes.dark), {
        DiscordSlot.accent: green.toARGB32(),
      });
      expect(DiscordPalettes.dark.diffFrom(DiscordPalettes.dark), isEmpty);
    });

    test('avatarColorFor is stable for the same seed', () {
      final first = DiscordPalettes.dark.avatarColorFor('@alice:example.org');
      final second = DiscordPalettes.dark.avatarColorFor('@alice:example.org');
      expect(first, second);
      expect(DiscordPalettes.dark.avatarPalette, contains(first));
    });
  });

  group('AppThemeState', () {
    test('round-trips through JSON', () {
      const state = AppThemeState(
        presetId: 'discord_light',
        overrides: {DiscordSlot.accent: 0xFF00FF00},
      );

      expect(AppThemeState.fromJson(state.toJson()), state);
    });

    test('resolve applies overrides on top of the preset', () {
      const state = AppThemeState(
        presetId: 'discord_light',
        overrides: {DiscordSlot.accent: 0xFF00FF00},
      );

      final colors = state.resolve();
      expect(colors.accent, const Color(0xFF00FF00));
      expect(colors.chatBackground, DiscordPalettes.light.chatBackground);
    });

    test('malformed JSON degrades to defaults instead of throwing', () {
      final state = AppThemeState.fromJson({
        'presetId': 42,
        'overrides': 'not a map',
      });

      expect(state.presetId, DiscordPalettes.defaultId);
      expect(state.overrides, isEmpty);
    });

    test('overrides survive a preset change', () {
      const state = AppThemeState(
        overrides: {DiscordSlot.accent: 0xFF00FF00},
      );
      final switched = state.copyWith(presetId: 'discord_light');

      expect(switched.resolve().accent, const Color(0xFF00FF00));
    });
  });
}

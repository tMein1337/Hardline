import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/injected_providers.dart';
import 'app_theme_state.dart';
import 'discord_colors.dart';
import 'discord_spacing.dart';
import 'theme_builder.dart';

const _themePrefsKey = 'app_theme_v1';

/// Owns the user's theme choice and persists it.
///
/// Preferences are read synchronously — they are loaded once in `main()` and
/// injected — so the first frame is already correctly themed and there is no
/// flash of default colors on launch.
class ThemeController extends Notifier<AppThemeState> {
  @override
  AppThemeState build() {
    final raw = ref.watch(prefsProvider).getString(_themePrefsKey);
    if (raw == null) return const AppThemeState();
    try {
      return AppThemeState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error, stack) {
      // A corrupt or hand-edited preference must never prevent startup.
      debugPrint('Ignoring unreadable saved theme: $error\n$stack');
      return const AppThemeState();
    }
  }

  /// Switches preset while keeping any per-slot customisations.
  Future<void> setPreset(String presetId) =>
      _persist(state.copyWith(presetId: presetId));

  Future<void> setOverride(String slot, Color color) => _persist(
    state.copyWith(
      overrides: {...state.overrides, slot: color.toARGB32()},
    ),
  );

  Future<void> clearOverride(String slot) => _persist(
    state.copyWith(overrides: {...state.overrides}..remove(slot)),
  );

  /// Drops all customisations but keeps the chosen preset.
  Future<void> clearAllOverrides() =>
      _persist(state.copyWith(overrides: const {}));

  Future<void> resetToDefaults() => _persist(const AppThemeState());

  Future<void> _persist(AppThemeState next) async {
    // Set state first so the repaint is immediate; the write can lag a frame.
    state = next;
    await ref
        .read(prefsProvider)
        .setString(_themePrefsKey, jsonEncode(next.toJson()));
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, AppThemeState>(ThemeController.new);

/// The resolved palette. Watch this (rather than the raw state) anywhere the
/// actual colors are needed outside the widget tree.
final discordColorsProvider = Provider<DiscordColors>(
  (ref) => ref.watch(themeControllerProvider).resolve(),
);

/// What `MaterialApp.theme` consumes.
final themeDataProvider = Provider<ThemeData>(
  (ref) => buildThemeData(
    ref.watch(discordColorsProvider),
    DiscordMetrics.standard,
  ),
);

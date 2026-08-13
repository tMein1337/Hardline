import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/injected_providers.dart';
import 'app_theme_state.dart';
import 'discord_colors.dart';
import 'discord_spacing.dart';
import 'theme_builder.dart';
import 'theme_library.dart';

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

  /// Selects a theme from the library by id.
  Future<void> setPreset(String presetId) =>
      _persist(state.copyWith(presetId: presetId));

  /// Drops the legacy override patch — see [AppThemeState.overrides].
  ///
  /// The only writer left, and it only ever writes empty: the appearance pane
  /// calls it once the patch has been saved as a theme, or discarded.
  Future<void> clearAllOverrides() =>
      _persist(state.copyWith(overrides: const {}));

  /// [commit] false while the slider is being dragged: state updates so the
  /// preview follows the thumb, but the write waits for `onChangeEnd`. Same
  /// deliberate exception `VoicePrefsController` makes for volumes.
  Future<void> setTooltipDelay(Duration delay, {bool commit = true}) {
    final clamped = Duration(
      milliseconds: delay.inMilliseconds.clamp(
        0,
        kMaxTooltipDelay.inMilliseconds,
      ),
    );
    return _persist(state.copyWith(tooltipDelay: clamped), write: commit);
  }

  Future<void> resetToDefaults() => _persist(const AppThemeState());

  /// [write] false defers the disk write to the caller's next committing call.
  /// Used while a slider is dragged, where every frame would otherwise be a
  /// separate write of a value the user has not settled on yet.
  Future<void> _persist(AppThemeState next, {bool write = true}) async {
    // Set state first so the repaint is immediate; the write can lag a frame.
    state = next;
    if (!write) return;
    await ref
        .read(prefsProvider)
        .setString(_themePrefsKey, jsonEncode(next.toJson()));
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, AppThemeState>(ThemeController.new);

/// The resolved palette. Watch this (rather than the raw state) anywhere the
/// actual colors are needed outside the widget tree.
///
/// The join between the two halves of theming: `themeControllerProvider` says
/// *which* theme, `themeLibraryProvider` says what it looks like. Watching both
/// is what makes editing a slot recolor the app on the next frame.
final discordColorsProvider = Provider<DiscordColors>((ref) {
  final state = ref.watch(themeControllerProvider);
  final library = ref.watch(themeLibraryProvider);
  return state.resolve(base: library.byId(state.presetId)?.toColors());
});

/// What `MaterialApp.theme` consumes.
final themeDataProvider = Provider<ThemeData>(
  (ref) => buildThemeData(
    ref.watch(discordColorsProvider),
    DiscordMetrics.standard,
    tooltipDelay: ref.watch(
      themeControllerProvider.select((state) => state.tooltipDelay),
    ),
  ),
);

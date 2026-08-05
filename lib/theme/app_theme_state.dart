import 'package:flutter/foundation.dart';

import 'discord_colors.dart';
import 'discord_palettes.dart';

/// The user's theme choice: a named preset plus any per-slot overrides.
///
/// Overrides are stored sparsely (only the slots actually changed) so that
/// switching presets still shows through for every slot the user has not
/// explicitly customised.
@immutable
class AppThemeState {
  const AppThemeState({
    this.presetId = DiscordPalettes.defaultId,
    this.overrides = const {},
  });

  final String presetId;

  /// Slot name (see `DiscordSlot`) to packed ARGB.
  final Map<String, int> overrides;

  /// The palette the app should actually render with.
  DiscordColors resolve() =>
      DiscordPalettes.byId(presetId).applyOverrides(overrides);

  AppThemeState copyWith({String? presetId, Map<String, int>? overrides}) =>
      AppThemeState(
        presetId: presetId ?? this.presetId,
        overrides: overrides ?? this.overrides,
      );

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'overrides': overrides,
  };

  /// Tolerant of malformed input: anything unparseable falls back to the
  /// default rather than preventing the app from starting.
  static AppThemeState fromJson(Map<String, dynamic> json) {
    final preset = json['presetId'];
    final raw = json['overrides'];
    return AppThemeState(
      presetId: preset is String && preset.isNotEmpty
          ? preset
          : DiscordPalettes.defaultId,
      overrides: raw is Map
          ? {
              for (final entry in raw.entries)
                if (entry.key is String && entry.value is int)
                  entry.key as String: entry.value as int,
            }
          : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppThemeState &&
          presetId == other.presetId &&
          mapEquals(overrides, other.overrides);

  @override
  int get hashCode => Object.hash(
    presetId,
    Object.hashAllUnordered(
      overrides.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

import 'package:flutter/foundation.dart';

import 'discord_colors.dart';
import 'discord_palettes.dart';

/// How long the pointer must rest on something before its tooltip appears.
///
/// Flutter's own default is `Duration.zero`, which on desktop means tooltips
/// erupt the instant the pointer crosses anything — unusable in a window this
/// dense. 400ms is what the theme hardcoded before this became a setting, kept
/// as the default so nobody's app changes behaviour by upgrading.
const kDefaultTooltipDelay = Duration(milliseconds: 400);

/// Upper bound offered in settings. Past this a tooltip reads as broken rather
/// than deliberate.
const kMaxTooltipDelay = Duration(seconds: 3);

/// The user's theme choice: a named preset, any per-slot overrides, and the
/// handful of interface preferences that reach every widget through
/// `ThemeData`.
///
/// Overrides are stored sparsely (only the slots actually changed) so that
/// switching presets still shows through for every slot the user has not
/// explicitly customised.
@immutable
class AppThemeState {
  const AppThemeState({
    this.presetId = DiscordPalettes.defaultId,
    this.overrides = const {},
    this.tooltipDelay = kDefaultTooltipDelay,
  });

  final String presetId;

  /// Slot name (see `DiscordSlot`) to packed ARGB.
  final Map<String, int> overrides;

  /// Hover time before a tooltip shows. `Duration.zero` means immediately.
  ///
  /// Lives here rather than in its own controller because it travels the same
  /// road as the colors: persisted with them, fed into `buildThemeData`, and
  /// applied by `MaterialApp` rebuilding — no widget has to know about it.
  final Duration tooltipDelay;

  /// The palette the app should actually render with.
  DiscordColors resolve() =>
      DiscordPalettes.byId(presetId).applyOverrides(overrides);

  AppThemeState copyWith({
    String? presetId,
    Map<String, int>? overrides,
    Duration? tooltipDelay,
  }) => AppThemeState(
    presetId: presetId ?? this.presetId,
    overrides: overrides ?? this.overrides,
    tooltipDelay: tooltipDelay ?? this.tooltipDelay,
  );

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'overrides': overrides,
    'tooltipDelayMs': tooltipDelay.inMilliseconds,
  };

  /// Tolerant of malformed input: anything unparseable falls back to the
  /// default rather than preventing the app from starting.
  static AppThemeState fromJson(Map<String, dynamic> json) {
    final preset = json['presetId'];
    final raw = json['overrides'];
    final delay = json['tooltipDelayMs'];

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
      // Clamped at parse time rather than at use: a hand-edited value of a
      // minute would otherwise be indistinguishable from tooltips being broken,
      // with nothing on screen to explain it.
      tooltipDelay: delay is int
          ? Duration(
              milliseconds: delay.clamp(0, kMaxTooltipDelay.inMilliseconds),
            )
          : kDefaultTooltipDelay,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppThemeState &&
          presetId == other.presetId &&
          tooltipDelay == other.tooltipDelay &&
          mapEquals(overrides, other.overrides);

  @override
  int get hashCode => Object.hash(
    presetId,
    tooltipDelay,
    Object.hashAllUnordered(
      overrides.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

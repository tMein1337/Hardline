// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'color_slots.dart';
import 'palettes.dart';
import 'theme_entry.dart';

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

/// How much larger or smaller than designed everything is drawn.
///
/// Multiplies both the type and the metrics — see `buildThemeData`. Scaling
/// only the type would grow the text inside rows whose height is fixed, so the
/// first thing a larger setting did would be to clip it.
const kDefaultTextScale = 1.0;

/// The range offered in settings.
///
/// The floor is set by the smallest tokens rather than by taste: `timestamp`
/// and `badge` are 11px, and 0.8 puts them just under 9, which is the point
/// where they stop being readable rather than merely small. The ceiling is
/// where the sidebar's fixed widths start to crowd — the rail and the channel
/// column do not scale, so past 1.5 a long channel name has nowhere to go.
const kMinTextScale = 0.8;
const kMaxTextScale = 1.5;

/// Which theme is selected, and the handful of interface preferences that
/// reach every widget through `ThemeData`.
///
/// The theme itself lives in the library (`theme_library.dart`); this only
/// names it. Keeping the selection here rather than in the library is what
/// gives the question "which theme is active" a single answer.
@immutable
class AppThemeState {
  const AppThemeState({
    this.presetId = AppPalettes.defaultId,
    this.overrides = const {},
    this.tooltipDelay = kDefaultTooltipDelay,
    this.textScale = kDefaultTextScale,
  });

  /// The id of the active theme — a key into the library, which seeds itself
  /// with the built-in ids this field held before the library existed.
  final String presetId;

  /// Slot name (see `ColorSlot`) to packed ARGB.
  ///
  /// **Legacy.** Before themes were a library, colours were customised as a
  /// sparse patch over whichever preset was selected, so that switching preset
  /// showed through for every slot left alone. Editing now happens *in* a theme
  /// instead, and nothing writes here any more.
  ///
  /// It is still read and still applied, so an installation that upgrades looks
  /// exactly as it did. The appearance pane offers to turn a non-empty patch
  /// into a real theme, or to discard it, and after that it stays empty
  /// forever. Removing the field outright would have silently reverted those
  /// users' colours on first launch.
  final Map<String, int> overrides;

  /// Hover time before a tooltip shows. `Duration.zero` means immediately.
  ///
  /// Lives here rather than in its own controller because it travels the same
  /// road as the colors: persisted with them, fed into `buildThemeData`, and
  /// applied by `MaterialApp` rebuilding — no widget has to know about it.
  final Duration tooltipDelay;

  /// See [kDefaultTextScale]. Travels the same road as [tooltipDelay].
  final double textScale;

  /// The palette the app should actually render with.
  ///
  /// [base] is the active theme's colours, which only the library can supply —
  /// see `paletteProvider`. Omitting it falls back to the built-in
  /// palette of the same id, which is what keeps this method usable from a
  /// test, and what renders if the library somehow does not know the id.
  AppPalette resolve({AppPalette? base}) =>
      (base ?? AppPalettes.byId(presetId)).applyOverrides(overrides);

  AppThemeState copyWith({
    String? presetId,
    Map<String, int>? overrides,
    Duration? tooltipDelay,
    double? textScale,
  }) => AppThemeState(
    presetId: presetId ?? this.presetId,
    overrides: overrides ?? this.overrides,
    tooltipDelay: tooltipDelay ?? this.tooltipDelay,
    textScale: textScale ?? this.textScale,
  );

  Map<String, dynamic> toJson() => {
    'presetId': presetId,
    'overrides': overrides,
    'tooltipDelayMs': tooltipDelay.inMilliseconds,
    'textScale': textScale,
  };

  /// Tolerant of malformed input: anything unparseable falls back to the
  /// default rather than preventing the app from starting.
  static AppThemeState fromJson(Map<String, dynamic> json) {
    final preset = json['presetId'];
    final raw = json['overrides'];
    final delay = json['tooltipDelayMs'];
    final scale = json['textScale'];

    return AppThemeState(
      presetId: preset is String && preset.isNotEmpty
          ? migratePresetId(preset)
          : AppPalettes.defaultId,
      overrides: raw is Map
          ? migrateSlotNames({
              for (final entry in raw.entries)
                if (entry.key is String && entry.value is int)
                  entry.key as String: entry.value as int,
            })
          : const {},
      // Clamped at parse time rather than at use: a hand-edited value of a
      // minute would otherwise be indistinguishable from tooltips being broken,
      // with nothing on screen to explain it.
      tooltipDelay: delay is int
          ? Duration(
              milliseconds: delay.clamp(0, kMaxTooltipDelay.inMilliseconds),
            )
          : kDefaultTooltipDelay,
      // Clamped at parse time for the same reason as the delay above: a
      // hand-edited 12 would render an app nobody could reach the settings of
      // to put it back.
      textScale: scale is num
          ? scale.toDouble().clamp(kMinTextScale, kMaxTextScale)
          : kDefaultTextScale,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppThemeState &&
          presetId == other.presetId &&
          tooltipDelay == other.tooltipDelay &&
          textScale == other.textScale &&
          mapEquals(overrides, other.overrides);

  @override
  int get hashCode => Object.hash(
    presetId,
    tooltipDelay,
    textScale,
    Object.hashAllUnordered(
      overrides.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'discord_colors.dart';
import 'discord_palettes.dart';

/// The longest a theme name may be.
///
/// Enforced on rename and on import rather than at render time: a row that
/// ellipsises is survivable, but a name pasted out of a file has no upper bound
/// at all, and a hundred kilobytes of it would be persisted forever.
const kMaxThemeNameLength = 60;

/// One theme in the library: a name and a value for every colour slot.
///
/// Unlike a palette in `discord_palettes.dart`, this is *data* — it is stored,
/// edited, copied and written to files. The colours are packed ARGB ints rather
/// than `Color`s because that is what both storage formats want, and converting
/// once at the edge ([toColors]) is cheaper than converting on every read.
///
/// [colors] is complete: every slot in [DiscordSlot.all] has a value. Nothing
/// constructs a partial entry — [ThemeEntry.fromColors] takes a whole palette,
/// and the file decoder fills any gap from [DiscordPalettes.dark] — so no
/// consumer has to handle a missing slot and render magenta.
@immutable
class ThemeEntry {
  const ThemeEntry({
    required this.id,
    required this.name,
    required this.colors,
    required this.avatarPalette,
  });

  /// Local to this installation, and never written to an exported file.
  ///
  /// The three seeded themes keep the preset ids the app already persisted
  /// (`discord_dark` and friends), which is what lets an existing `presetId`
  /// keep selecting the right theme across this change without a migration.
  final String id;

  final String name;

  /// Slot name (see [DiscordSlot]) to packed ARGB. Treat as immutable.
  final Map<String, int> colors;

  /// Fallback avatar colours, packed ARGB. Carried faithfully through copies,
  /// export and import, but there is no editor for it — see the README.
  final List<int> avatarPalette;

  /// Whether this entry still occupies one of the three built-in ids, and can
  /// therefore be compared against — or restored from — a `const` palette.
  ///
  /// False for a duplicate of a built-in: the copy gets a generated id, so the
  /// original stays revertible while the copy is freely editable.
  bool get isSeeded => DiscordPalettes.byIdMap.containsKey(id);

  DiscordColors toColors() => DiscordColors(
    slots: {
      for (final entry in colors.entries) entry.key: Color(entry.value),
    },
    avatarPalette: [for (final value in avatarPalette) Color(value)],
  );

  static ThemeEntry fromColors({
    required String id,
    required String name,
    required DiscordColors colors,
  }) => ThemeEntry(
    id: id,
    name: name,
    colors: colors.toJson(),
    avatarPalette: [
      for (final color in colors.avatarPalette) color.toARGB32(),
    ],
  );

  /// An independent copy under a new [id] and [name].
  ///
  /// The maps and lists are rebuilt rather than shared, so editing a slot on
  /// the copy cannot reach back into the original — the failure this guards
  /// against is invisible until someone duplicates a theme and watches both
  /// change together.
  ThemeEntry copyAs({required String id, required String name}) => ThemeEntry(
    id: id,
    name: name,
    colors: {...colors},
    avatarPalette: [...avatarPalette],
  );

  ThemeEntry copyWith({String? name, Map<String, int>? colors}) => ThemeEntry(
    id: id,
    name: name ?? this.name,
    // Merged, not replaced, matching `DiscordColors.copyWith`: callers pass
    // only the slot they are changing.
    colors: colors == null ? this.colors : {...this.colors, ...colors},
    avatarPalette: avatarPalette,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'colors': colors,
    'avatarPalette': avatarPalette,
  };

  /// Null for anything unusable, so one corrupt entry drops out of the library
  /// instead of taking the whole list — and with it every theme — down.
  ///
  /// A stored entry missing slots is completed from [DiscordPalettes.dark]
  /// rather than rejected: the alternative is losing a theme somebody built
  /// because a slot was added to the app after they saved it.
  static ThemeEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;

    final rawColors = json['colors'];
    if (rawColors is! Map) return null;

    final colors = <String, int>{
      for (final entry in rawColors.entries)
        if (entry.key is String && entry.value is int)
          entry.key as String: entry.value as int,
    };

    final rawRamp = json['avatarPalette'];
    final ramp = rawRamp is List
        ? [
            for (final value in rawRamp)
              if (value is int) value,
          ]
        : const <int>[];

    return ThemeEntry(
      id: id,
      name: clampThemeName(name),
      colors: completeColors(colors),
      avatarPalette: ramp.isEmpty ? defaultAvatarPalette : ramp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeEntry &&
          id == other.id &&
          name == other.name &&
          mapEquals(colors, other.colors) &&
          listEquals(avatarPalette, other.avatarPalette);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAllUnordered(
      colors.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(avatarPalette),
  );
}

/// Every theme the app knows about, in the order they are shown.
///
/// Same shape as `AccountsState` and `AppThemeState`: immutable, JSON round
/// trip, and a `fromJson` that degrades rather than throws. Which theme is
/// *active* deliberately lives elsewhere — `AppThemeState.presetId` already
/// held that, and duplicating it here would give two answers to one question.
@immutable
class ThemeLibraryState {
  const ThemeLibraryState({this.entries = const []});

  final List<ThemeEntry> entries;

  ThemeEntry? byId(String? id) =>
      id == null ? null : entries.where((e) => e.id == id).firstOrNull;

  int indexOf(String id) => entries.indexWhere((e) => e.id == id);

  bool get isEmpty => entries.isEmpty;

  /// Which of the three built-in themes are no longer in the library, in their
  /// original order. Drives the *Restore built-in themes* action.
  List<String> get missingSeededIds => [
    for (final id in DiscordPalettes.byIdMap.keys)
      if (byId(id) == null) id,
  ];

  /// [wanted], or [wanted] with a numeric suffix if that name is taken.
  ///
  /// Names are not identities — two themes may share one without anything
  /// breaking — but a list with three rows reading "Midnight" is unusable, so
  /// duplicate, import and rename all come through here.
  ///
  /// [exceptId] is the entry being renamed, which must not count as a clash
  /// with itself: without it, confirming a rename dialog without changing
  /// anything would turn "Midnight" into "Midnight (2)".
  String uniqueName(String wanted, {String? exceptId}) {
    bool free(String candidate) =>
        entries.every((e) => e.id == exceptId || e.name != candidate);

    final base = clampThemeName(wanted);
    if (free(base)) return base;

    for (var suffix = 2; ; suffix++) {
      final candidate = clampThemeName('$base ($suffix)');
      if (free(candidate)) return candidate;
    }
  }

  ThemeLibraryState copyWith({List<ThemeEntry>? entries}) =>
      ThemeLibraryState(entries: entries ?? this.entries);

  Map<String, Object?> toJson() => {
    'version': 1,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  static ThemeLibraryState fromJson(Map<String, Object?> json) {
    final raw = json['entries'];
    return ThemeLibraryState(
      entries: raw is List
          ? [for (final item in raw) ?ThemeEntry.fromJson(item)]
          : const [],
    );
  }

  /// The three built-in palettes as ordinary entries.
  ///
  /// What a fresh installation starts with, and what *Restore built-in themes*
  /// draws from. They are seeds, not a separate kind of theme: once here they
  /// can be renamed, edited and deleted like anything else.
  static ThemeLibraryState seeded() => ThemeLibraryState(
    entries: [
      for (final entry in DiscordPalettes.byIdMap.entries)
        ThemeEntry.fromColors(
          id: entry.key,
          name: DiscordPalettes.labels[entry.key] ?? entry.key,
          colors: entry.value,
        ),
    ],
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeLibraryState && listEquals(entries, other.entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

/// A theme with every slot filled: [colors] where it has an answer, and
/// [DiscordPalettes.dark] where it does not.
///
/// Both readers need this. A stored theme predates any slot added since it was
/// saved, and an imported file may have been hand-written — in either case an
/// incomplete palette renders as magenta, which is worse than a colour the user
/// did not choose.
Map<String, int> completeColors(Map<String, int> colors) => {
  for (final slot in DiscordSlot.all)
    // Unknown keys in `colors` are dropped by iterating the slot list rather
    // than the input: a file from a future version can name slots this build
    // has never heard of, and they are not ours to keep.
    slot: colors[slot] ?? DiscordPalettes.dark.slot(slot).toARGB32(),
};

/// The built-in avatar ramp, for entries that carry none of their own.
final List<int> defaultAvatarPalette = [
  for (final color in DiscordPalettes.dark.avatarPalette) color.toARGB32(),
];

/// Trimmed and capped, or a placeholder if there is nothing left.
String clampThemeName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return 'Untitled theme';
  return trimmed.length <= kMaxThemeNameLength
      ? trimmed
      : trimmed.substring(0, kMaxThemeNameLength).trimRight();
}

/// A fresh id for a theme the user created, duplicated or imported.
///
/// Random rather than sequential, and never one of the built-in ids, so a
/// generated id cannot collide with a seed that is currently deleted and about
/// to be restored.
String generateThemeId([Random? random]) {
  final source = random ?? Random();
  final value = source.nextInt(1 << 32).toRadixString(36);
  final salt = source.nextInt(1 << 32).toRadixString(36);
  return 'theme_$value$salt';
}

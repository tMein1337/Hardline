import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Every semantic color slot the UI can ask for.
///
/// Widgets never name a hex value; they name a *role* from this list. The
/// concrete colors for each role live in `discord_palettes.dart`, which is the
/// only file in the project allowed to contain hex literals.
///
/// Adding a slot is a three-step change: add the constant here, add it to
/// [DiscordSlot.all], and give it a value in every palette.
abstract final class DiscordSlot {
  // Surfaces, darkest to lightest.
  static const serverRail = 'serverRail';
  static const channelSidebar = 'channelSidebar';
  static const chatBackground = 'chatBackground';
  static const elevatedSurface = 'elevatedSurface';
  static const floatingSurface = 'floatingSurface';
  static const scrim = 'scrim';

  // Interaction states.
  static const messageHover = 'messageHover';
  static const listItemHover = 'listItemHover';
  static const listItemSelected = 'listItemSelected';
  static const railIdle = 'railIdle';
  static const railHover = 'railHover';

  // Text.
  static const textPrimary = 'textPrimary';
  static const textHeader = 'textHeader';
  static const textMuted = 'textMuted';
  static const textFaint = 'textFaint';
  static const textLink = 'textLink';
  static const textOnAccent = 'textOnAccent';

  // Accent and semantic.
  static const accent = 'accent';
  static const accentHover = 'accentHover';
  static const accentPressed = 'accentPressed';
  static const danger = 'danger';
  static const success = 'success';
  static const warning = 'warning';

  // Mentions and unread.
  static const mentionBackground = 'mentionBackground';
  static const mentionHoverBackground = 'mentionHoverBackground';
  static const mentionBar = 'mentionBar';
  static const unreadBadge = 'unreadBadge';
  static const unreadBadgeText = 'unreadBadgeText';
  static const unreadDot = 'unreadDot';

  // Structure.
  static const divider = 'divider';
  static const dividerStrong = 'dividerStrong';
  static const scrollbarThumb = 'scrollbarThumb';
  static const scrollbarTrack = 'scrollbarTrack';

  // Inputs.
  static const inputBackground = 'inputBackground';
  static const inputBackgroundAlt = 'inputBackgroundAlt';
  static const inputBorder = 'inputBorder';
  static const inputBorderFocused = 'inputBorderFocused';

  /// Drives the settings screen's picker list and validates palettes.
  static const List<String> all = [
    serverRail,
    channelSidebar,
    chatBackground,
    elevatedSurface,
    floatingSurface,
    scrim,
    messageHover,
    listItemHover,
    listItemSelected,
    railIdle,
    railHover,
    textPrimary,
    textHeader,
    textMuted,
    textFaint,
    textLink,
    textOnAccent,
    accent,
    accentHover,
    accentPressed,
    danger,
    success,
    warning,
    mentionBackground,
    mentionHoverBackground,
    mentionBar,
    unreadBadge,
    unreadBadgeText,
    unreadDot,
    divider,
    dividerStrong,
    scrollbarThumb,
    scrollbarTrack,
    inputBackground,
    inputBackgroundAlt,
    inputBorder,
    inputBorderFocused,
  ];

  /// Human-readable labels for a future settings UI.
  static String labelOf(String slot) {
    final withSpaces = slot.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => ' ${m[0]!.toLowerCase()}',
    );
    return withSpaces[0].toUpperCase() + withSpaces.substring(1);
  }
}

/// The app's color palette, attached to [ThemeData.extensions].
///
/// Colors are held in a map keyed by [DiscordSlot] rather than as individual
/// fields. That keeps [lerp], [copyWith], [applyOverrides] and JSON generic, so
/// adding a slot cannot silently miss one of them — a bug class that is
/// invisible at runtime because the app keeps working with a stale color.
@immutable
class DiscordColors extends ThemeExtension<DiscordColors> {
  const DiscordColors({required this.slots, required this.avatarPalette});

  /// Slot name (see [DiscordSlot]) to color. Treat as immutable.
  final Map<String, Color> slots;

  /// Deterministic fallback colors for users with no avatar.
  final List<Color> avatarPalette;

  /// Loud magenta so a missing slot is obvious on screen rather than silently
  /// rendering as transparent or black.
  static const _missing = Color(0xFFFF00FF);

  Color slot(String name) {
    final color = slots[name];
    assert(color != null, 'DiscordColors is missing slot "$name"');
    return color ?? _missing;
  }

  /// Picks a stable avatar color for [seed] (a user or room id).
  Color avatarColorFor(String seed) =>
      avatarPalette[seed.hashCode.abs() % avatarPalette.length];

  // ── Typed accessors ────────────────────────────────────────────────────
  Color get serverRail => slot(DiscordSlot.serverRail);
  Color get channelSidebar => slot(DiscordSlot.channelSidebar);
  Color get chatBackground => slot(DiscordSlot.chatBackground);
  Color get elevatedSurface => slot(DiscordSlot.elevatedSurface);
  Color get floatingSurface => slot(DiscordSlot.floatingSurface);
  Color get scrim => slot(DiscordSlot.scrim);

  Color get messageHover => slot(DiscordSlot.messageHover);
  Color get listItemHover => slot(DiscordSlot.listItemHover);
  Color get listItemSelected => slot(DiscordSlot.listItemSelected);
  Color get railIdle => slot(DiscordSlot.railIdle);
  Color get railHover => slot(DiscordSlot.railHover);

  Color get textPrimary => slot(DiscordSlot.textPrimary);
  Color get textHeader => slot(DiscordSlot.textHeader);
  Color get textMuted => slot(DiscordSlot.textMuted);
  Color get textFaint => slot(DiscordSlot.textFaint);
  Color get textLink => slot(DiscordSlot.textLink);
  Color get textOnAccent => slot(DiscordSlot.textOnAccent);

  Color get accent => slot(DiscordSlot.accent);
  Color get accentHover => slot(DiscordSlot.accentHover);
  Color get accentPressed => slot(DiscordSlot.accentPressed);
  Color get danger => slot(DiscordSlot.danger);
  Color get success => slot(DiscordSlot.success);
  Color get warning => slot(DiscordSlot.warning);

  Color get mentionBackground => slot(DiscordSlot.mentionBackground);
  Color get mentionHoverBackground => slot(DiscordSlot.mentionHoverBackground);
  Color get mentionBar => slot(DiscordSlot.mentionBar);
  Color get unreadBadge => slot(DiscordSlot.unreadBadge);
  Color get unreadBadgeText => slot(DiscordSlot.unreadBadgeText);
  Color get unreadDot => slot(DiscordSlot.unreadDot);

  Color get divider => slot(DiscordSlot.divider);
  Color get dividerStrong => slot(DiscordSlot.dividerStrong);
  Color get scrollbarThumb => slot(DiscordSlot.scrollbarThumb);
  Color get scrollbarTrack => slot(DiscordSlot.scrollbarTrack);

  Color get inputBackground => slot(DiscordSlot.inputBackground);
  Color get inputBackgroundAlt => slot(DiscordSlot.inputBackgroundAlt);
  Color get inputBorder => slot(DiscordSlot.inputBorder);
  Color get inputBorderFocused => slot(DiscordSlot.inputBorderFocused);

  /// True when the palette reads as dark, used to pick a [Brightness].
  bool get isDark => chatBackground.computeLuminance() < 0.5;

  // ── ThemeExtension ─────────────────────────────────────────────────────
  @override
  DiscordColors copyWith({
    Map<String, Color>? slots,
    List<Color>? avatarPalette,
  }) {
    return DiscordColors(
      // Merged, not replaced: callers pass only the slots they are changing.
      slots: slots == null ? this.slots : {...this.slots, ...slots},
      avatarPalette: avatarPalette ?? this.avatarPalette,
    );
  }

  @override
  DiscordColors lerp(covariant DiscordColors? other, double t) {
    if (other == null) return this;
    return DiscordColors(
      slots: {
        for (final name in slots.keys)
          name: Color.lerp(slot(name), other.slot(name), t)!,
      },
      avatarPalette: [
        for (var i = 0; i < avatarPalette.length; i++)
          Color.lerp(
            avatarPalette[i],
            i < other.avatarPalette.length
                ? other.avatarPalette[i]
                : avatarPalette[i],
            t,
          )!,
      ],
    );
  }

  // ── Customization support ──────────────────────────────────────────────

  /// Applies user overrides on top of this palette. Unknown slot names are
  /// ignored so a stale saved preference can never crash startup.
  DiscordColors applyOverrides(Map<String, int> overrides) {
    if (overrides.isEmpty) return this;
    final patch = <String, Color>{};
    for (final entry in overrides.entries) {
      if (slots.containsKey(entry.key)) patch[entry.key] = Color(entry.value);
    }
    return patch.isEmpty ? this : copyWith(slots: patch);
  }

  /// The sparse set of slots where this palette differs from [base] — what a
  /// settings screen persists, so preset changes still show through.
  Map<String, int> diffFrom(DiscordColors base) => {
    for (final name in slots.keys)
      if (slot(name) != base.slot(name)) name: slot(name).toARGB32(),
  };

  Map<String, int> toJson() => {
    for (final entry in slots.entries) entry.key: entry.value.toARGB32(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscordColors &&
          mapEquals(slots, other.slots) &&
          listEquals(avatarPalette, other.avatarPalette);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      slots.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(avatarPalette),
  );
}

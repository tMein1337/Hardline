// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Every semantic color slot the UI can ask for.
///
/// Widgets never name a hex value; they name a *role* from this list. The
/// concrete colors for each role live in `palettes.dart`, which is the
/// only file in the project allowed to contain hex literals.
///
/// Adding a slot is a four-step change: add the constant here, add it to
/// [ColorSlot.all], add a typed accessor on [AppPalette], and give it a
/// value in every palette. `color_slots_test.dart` enforces the last step.
abstract final class ColorSlot {
  // Surfaces, darkest to lightest.
  static const spaceRail = 'spaceRail';
  static const roomSidebar = 'roomSidebar';
  static const timelineBackground = 'timelineBackground';
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

  // Attachments.
  //
  // `dropOverlay` is its own slot rather than a reuse of `scrim`: a black wash
  // over the chat reads as a modal dialog, not as "let go here".
  static const attachmentCard = 'attachmentCard';
  static const attachmentCardBorder = 'attachmentCardBorder';
  static const attachmentPlaceholder = 'attachmentPlaceholder';
  static const attachmentTray = 'attachmentTray';
  static const attachmentChip = 'attachmentChip';
  static const dropOverlay = 'dropOverlay';
  static const dropBorder = 'dropBorder';

  // Voice and video.
  //
  // Kept separate from the semantic slots above (rather than reusing `success`
  // and `danger`) so the call UI can be recolored on its own. Call state is its
  // own annunciator language here — green for a live call, amber for one
  // connecting — and folding it into the generic states would mean recoloring
  // every success message just to restyle a call.
  static const voiceConnected = 'voiceConnected';
  static const voiceConnecting = 'voiceConnecting';
  static const voiceError = 'voiceError';
  static const voiceSpeakingRing = 'voiceSpeakingRing';
  static const voiceMutedIcon = 'voiceMutedIcon';
  static const voiceDeafenedIcon = 'voiceDeafenedIcon';
  static const voiceParticipantRow = 'voiceParticipantRow';
  static const voiceParticipantRowHover = 'voiceParticipantRowHover';
  static const voiceControlBar = 'voiceControlBar';
  static const voiceControlIcon = 'voiceControlIcon';
  static const voiceControlIconActive = 'voiceControlIconActive';
  static const voiceControlDanger = 'voiceControlDanger';
  static const videoTileBackground = 'videoTileBackground';
  static const videoTilePlaceholder = 'videoTilePlaceholder';
  static const volumeSliderTrack = 'volumeSliderTrack';
  static const volumeSliderActive = 'volumeSliderActive';

  /// Drives the settings screen's picker list and validates palettes.
  static const List<String> all = [
    spaceRail,
    roomSidebar,
    timelineBackground,
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
    attachmentCard,
    attachmentCardBorder,
    attachmentPlaceholder,
    attachmentTray,
    attachmentChip,
    dropOverlay,
    dropBorder,
    voiceConnected,
    voiceConnecting,
    voiceError,
    voiceSpeakingRing,
    voiceMutedIcon,
    voiceDeafenedIcon,
    voiceParticipantRow,
    voiceParticipantRowHover,
    voiceControlBar,
    voiceControlIcon,
    voiceControlIconActive,
    voiceControlDanger,
    videoTileBackground,
    videoTilePlaceholder,
    volumeSliderTrack,
    volumeSliderActive,
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
/// Colors are held in a map keyed by [ColorSlot] rather than as individual
/// fields. That keeps [lerp], [copyWith], [applyOverrides] and JSON generic, so
/// adding a slot cannot silently miss one of them — a bug class that is
/// invisible at runtime because the app keeps working with a stale color.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({required this.slots, required this.avatarPalette});

  /// Slot name (see [ColorSlot]) to color. Treat as immutable.
  final Map<String, Color> slots;

  /// Deterministic fallback colors for users with no avatar.
  final List<Color> avatarPalette;

  /// Loud magenta so a missing slot is obvious on screen rather than silently
  /// rendering as transparent or black.
  static const _missing = Color(0xFFFF00FF);

  Color slot(String name) {
    final color = slots[name];
    assert(color != null, 'AppPalette is missing slot "$name"');
    return color ?? _missing;
  }

  /// Picks a stable avatar color for [seed] (a user or room id).
  Color avatarColorFor(String seed) =>
      avatarPalette[seed.hashCode.abs() % avatarPalette.length];

  // ── Typed accessors ────────────────────────────────────────────────────
  Color get spaceRail => slot(ColorSlot.spaceRail);
  Color get roomSidebar => slot(ColorSlot.roomSidebar);
  Color get timelineBackground => slot(ColorSlot.timelineBackground);
  Color get elevatedSurface => slot(ColorSlot.elevatedSurface);
  Color get floatingSurface => slot(ColorSlot.floatingSurface);
  Color get scrim => slot(ColorSlot.scrim);

  Color get messageHover => slot(ColorSlot.messageHover);
  Color get listItemHover => slot(ColorSlot.listItemHover);
  Color get listItemSelected => slot(ColorSlot.listItemSelected);
  Color get railIdle => slot(ColorSlot.railIdle);
  Color get railHover => slot(ColorSlot.railHover);

  Color get textPrimary => slot(ColorSlot.textPrimary);
  Color get textHeader => slot(ColorSlot.textHeader);
  Color get textMuted => slot(ColorSlot.textMuted);
  Color get textFaint => slot(ColorSlot.textFaint);
  Color get textLink => slot(ColorSlot.textLink);
  Color get textOnAccent => slot(ColorSlot.textOnAccent);

  Color get accent => slot(ColorSlot.accent);
  Color get accentHover => slot(ColorSlot.accentHover);
  Color get accentPressed => slot(ColorSlot.accentPressed);
  Color get danger => slot(ColorSlot.danger);
  Color get success => slot(ColorSlot.success);
  Color get warning => slot(ColorSlot.warning);

  Color get mentionBackground => slot(ColorSlot.mentionBackground);
  Color get mentionHoverBackground => slot(ColorSlot.mentionHoverBackground);
  Color get mentionBar => slot(ColorSlot.mentionBar);
  Color get unreadBadge => slot(ColorSlot.unreadBadge);
  Color get unreadBadgeText => slot(ColorSlot.unreadBadgeText);
  Color get unreadDot => slot(ColorSlot.unreadDot);

  Color get divider => slot(ColorSlot.divider);
  Color get dividerStrong => slot(ColorSlot.dividerStrong);
  Color get scrollbarThumb => slot(ColorSlot.scrollbarThumb);
  Color get scrollbarTrack => slot(ColorSlot.scrollbarTrack);

  Color get inputBackground => slot(ColorSlot.inputBackground);
  Color get inputBackgroundAlt => slot(ColorSlot.inputBackgroundAlt);
  Color get inputBorder => slot(ColorSlot.inputBorder);
  Color get inputBorderFocused => slot(ColorSlot.inputBorderFocused);

  Color get attachmentCard => slot(ColorSlot.attachmentCard);
  Color get attachmentCardBorder => slot(ColorSlot.attachmentCardBorder);
  Color get attachmentPlaceholder => slot(ColorSlot.attachmentPlaceholder);
  Color get attachmentTray => slot(ColorSlot.attachmentTray);
  Color get attachmentChip => slot(ColorSlot.attachmentChip);
  Color get dropOverlay => slot(ColorSlot.dropOverlay);
  Color get dropBorder => slot(ColorSlot.dropBorder);

  Color get voiceConnected => slot(ColorSlot.voiceConnected);
  Color get voiceConnecting => slot(ColorSlot.voiceConnecting);
  Color get voiceError => slot(ColorSlot.voiceError);
  Color get voiceSpeakingRing => slot(ColorSlot.voiceSpeakingRing);
  Color get voiceMutedIcon => slot(ColorSlot.voiceMutedIcon);
  Color get voiceDeafenedIcon => slot(ColorSlot.voiceDeafenedIcon);
  Color get voiceParticipantRow => slot(ColorSlot.voiceParticipantRow);
  Color get voiceParticipantRowHover =>
      slot(ColorSlot.voiceParticipantRowHover);
  Color get voiceControlBar => slot(ColorSlot.voiceControlBar);
  Color get voiceControlIcon => slot(ColorSlot.voiceControlIcon);
  Color get voiceControlIconActive => slot(ColorSlot.voiceControlIconActive);
  Color get voiceControlDanger => slot(ColorSlot.voiceControlDanger);
  Color get videoTileBackground => slot(ColorSlot.videoTileBackground);
  Color get videoTilePlaceholder => slot(ColorSlot.videoTilePlaceholder);
  Color get volumeSliderTrack => slot(ColorSlot.volumeSliderTrack);
  Color get volumeSliderActive => slot(ColorSlot.volumeSliderActive);

  /// True when the palette reads as dark, used to pick a [Brightness].
  bool get isDark => timelineBackground.computeLuminance() < 0.5;

  // ── ThemeExtension ─────────────────────────────────────────────────────
  @override
  AppPalette copyWith({
    Map<String, Color>? slots,
    List<Color>? avatarPalette,
  }) {
    return AppPalette(
      // Merged, not replaced: callers pass only the slots they are changing.
      slots: slots == null ? this.slots : {...this.slots, ...slots},
      avatarPalette: avatarPalette ?? this.avatarPalette,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
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
  AppPalette applyOverrides(Map<String, int> overrides) {
    if (overrides.isEmpty) return this;
    final patch = <String, Color>{};
    for (final entry in overrides.entries) {
      if (slots.containsKey(entry.key)) patch[entry.key] = Color(entry.value);
    }
    return patch.isEmpty ? this : copyWith(slots: patch);
  }

  /// The sparse set of slots where this palette differs from [base] — what a
  /// settings screen persists, so preset changes still show through.
  Map<String, int> diffFrom(AppPalette base) => {
    for (final name in slots.keys)
      if (slot(name) != base.slot(name)) name: slot(name).toARGB32(),
  };

  Map<String, int> toJson() => {
    for (final entry in slots.entries) entry.key: entry.value.toARGB32(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppPalette &&
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

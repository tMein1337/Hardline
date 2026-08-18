// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'color_slots.dart';

/// The built-in palettes.
///
/// This is the ONLY file in the project that may contain hex color literals.
/// Everywhere else, widgets read roles through `context.colors`. Keeping the
/// values here is what lets a settings screen recolor the whole app later
/// without touching a single widget.
///
/// A palette must define every slot in [ColorSlot.all]; the theme test
/// asserts this, because a missing slot renders as loud magenta at runtime.
///
/// ## The design language
///
/// Hardline is styled after an airliner glass cockpit: a black panel, data in
/// white, and a small vocabulary of saturated instrument colours that always
/// mean the same thing wherever they appear.
///
///   orange  — the accent. Selection, focus, the app's own voice.
///   green   — normal / engaged. A call that is up, a device that is verified.
///   amber   — caution. Something in progress or needing attention.
///   red     — warning. Failure, mute, an unread you were named in.
///   cyan    — reference information. Links and inert annotations.
///
/// Surfaces are near-black and separated by very little luminance, the way a
/// bezel is separated from a display; structure comes from thin rules and from
/// the accent, not from a staircase of greys.
abstract final class AppPalettes {
  /// The app default: a lit flight deck at night.
  static const dark = AppPalette(
    slots: {
      ColorSlot.spaceRail: Color(0xFF0A0A0B),
      ColorSlot.roomSidebar: Color(0xFF101012),
      ColorSlot.timelineBackground: Color(0xFF151517),
      ColorSlot.elevatedSurface: Color(0xFF1E1E21),
      // Darker than every other surface: a menu reads as a bezel laid on top
      // of the panel rather than as a lighter card floating above it.
      ColorSlot.floatingSurface: Color(0xFF08080A),
      ColorSlot.scrim: Color(0xCC000000),

      ColorSlot.messageHover: Color(0xFF1B1B1E),
      ColorSlot.listItemHover: Color(0xFF1F1F23),
      // Warm rather than neutral: a selected row is tinted towards the accent,
      // which is what "armed" looks like on a mode control panel.
      ColorSlot.listItemSelected: Color(0xFF2A2118),
      ColorSlot.railIdle: Color(0xFF17171A),
      ColorSlot.railHover: Color(0xFFFF7A18),

      ColorSlot.textPrimary: Color(0xFFD6D6D9),
      ColorSlot.textHeader: Color(0xFFF5F5F7),
      ColorSlot.textMuted: Color(0xFF8A8A92),
      ColorSlot.textFaint: Color(0xFF5E5E66),
      ColorSlot.textLink: Color(0xFF4FC3F7),
      // Black on orange. The accent is bright enough that white on it is the
      // weaker pairing, and dark-on-amber is how a caption on a lit annunciator
      // actually reads.
      ColorSlot.textOnAccent: Color(0xFF0A0A0B),

      ColorSlot.accent: Color(0xFFFF7A18),
      ColorSlot.accentHover: Color(0xFFFF8F3C),
      ColorSlot.accentPressed: Color(0xFFD8620F),
      ColorSlot.danger: Color(0xFFFF3B30),
      ColorSlot.success: Color(0xFF2ECC71),
      ColorSlot.warning: Color(0xFFFFB302),

      ColorSlot.mentionBackground: Color(0xFF241A10),
      ColorSlot.mentionHoverBackground: Color(0xFF2E2114),
      ColorSlot.mentionBar: Color(0xFFFF7A18),
      ColorSlot.unreadBadge: Color(0xFFFF3B30),
      ColorSlot.unreadBadgeText: Color(0xFFFFFFFF),
      ColorSlot.unreadDot: Color(0xFFFF7A18),

      ColorSlot.divider: Color(0xFF232327),
      ColorSlot.dividerStrong: Color(0xFF000000),
      ColorSlot.scrollbarThumb: Color(0xFF35353B),
      ColorSlot.scrollbarTrack: Color(0xFF0F0F11),

      ColorSlot.inputBackground: Color(0xFF1A1A1D),
      ColorSlot.inputBackgroundAlt: Color(0xFF0C0C0E),
      ColorSlot.inputBorder: Color(0xFF2A2A2F),
      ColorSlot.inputBorderFocused: Color(0xFFFF7A18),

      ColorSlot.attachmentCard: Color(0xFF141416),
      ColorSlot.attachmentCardBorder: Color(0xFF26262B),
      ColorSlot.attachmentPlaceholder: Color(0xFF1A1A1D),
      ColorSlot.attachmentTray: Color(0xFF111113),
      ColorSlot.attachmentChip: Color(0xFF1C1C20),
      ColorSlot.dropOverlay: Color(0xE60A0A0B),
      ColorSlot.dropBorder: Color(0xFFFF7A18),

      // Annunciator language: green is normal, amber is caution, red is
      // warning. The speaking ring is the accent instead of green, so "someone
      // is talking" is not competing with "the call is up".
      ColorSlot.voiceConnected: Color(0xFF2ECC71),
      ColorSlot.voiceConnecting: Color(0xFFFFB302),
      ColorSlot.voiceError: Color(0xFFFF3B30),
      ColorSlot.voiceSpeakingRing: Color(0xFFFF7A18),
      ColorSlot.voiceMutedIcon: Color(0xFFFF3B30),
      ColorSlot.voiceDeafenedIcon: Color(0xFFFF3B30),
      ColorSlot.voiceParticipantRow: Color(0x00000000),
      ColorSlot.voiceParticipantRowHover: Color(0xFF1F1F23),
      ColorSlot.voiceControlBar: Color(0xFF0C0C0E),
      ColorSlot.voiceControlIcon: Color(0xFF9A9AA2),
      ColorSlot.voiceControlIconActive: Color(0xFFFF7A18),
      ColorSlot.voiceControlDanger: Color(0xFFFF3B30),
      ColorSlot.videoTileBackground: Color(0xFF000000),
      ColorSlot.videoTilePlaceholder: Color(0xFF111113),
      ColorSlot.volumeSliderTrack: Color(0xFF2A2A2F),
      ColorSlot.volumeSliderActive: Color(0xFFFF7A18),
    },
    avatarPalette: _avatarRamp,
  );

  /// Dimmed for a dark room: the same layout with the panel brightness turned
  /// down, which is what the cockpit does on a night sector.
  static const night = AppPalette(
    slots: {
      ColorSlot.spaceRail: Color(0xFF050506),
      ColorSlot.roomSidebar: Color(0xFF090909),
      ColorSlot.timelineBackground: Color(0xFF0C0C0D),
      ColorSlot.elevatedSurface: Color(0xFF141416),
      ColorSlot.floatingSurface: Color(0xFF000000),
      ColorSlot.scrim: Color(0xE0000000),

      ColorSlot.messageHover: Color(0xFF121213),
      ColorSlot.listItemHover: Color(0xFF161618),
      ColorSlot.listItemSelected: Color(0xFF20180F),
      ColorSlot.railIdle: Color(0xFF101011),
      ColorSlot.railHover: Color(0xFFC85E10),

      ColorSlot.textPrimary: Color(0xFFB4B4B8),
      ColorSlot.textHeader: Color(0xFFDCDCE0),
      ColorSlot.textMuted: Color(0xFF70707A),
      ColorSlot.textFaint: Color(0xFF4B4B54),
      ColorSlot.textLink: Color(0xFF3B9BC7),
      ColorSlot.textOnAccent: Color(0xFF050506),

      ColorSlot.accent: Color(0xFFC85E10),
      ColorSlot.accentHover: Color(0xFFE07020),
      ColorSlot.accentPressed: Color(0xFF9E4A0C),
      ColorSlot.danger: Color(0xFFC72E26),
      ColorSlot.success: Color(0xFF229E56),
      ColorSlot.warning: Color(0xFFC78A02),

      ColorSlot.mentionBackground: Color(0xFF1B140C),
      ColorSlot.mentionHoverBackground: Color(0xFF241A0F),
      ColorSlot.mentionBar: Color(0xFFC85E10),
      ColorSlot.unreadBadge: Color(0xFFC72E26),
      ColorSlot.unreadBadgeText: Color(0xFFE8E8EA),
      ColorSlot.unreadDot: Color(0xFFC85E10),

      ColorSlot.divider: Color(0xFF1A1A1D),
      ColorSlot.dividerStrong: Color(0xFF000000),
      ColorSlot.scrollbarThumb: Color(0xFF28282D),
      ColorSlot.scrollbarTrack: Color(0xFF090909),

      ColorSlot.inputBackground: Color(0xFF121214),
      ColorSlot.inputBackgroundAlt: Color(0xFF060607),
      ColorSlot.inputBorder: Color(0xFF1F1F23),
      ColorSlot.inputBorderFocused: Color(0xFFC85E10),

      ColorSlot.attachmentCard: Color(0xFF0F0F10),
      ColorSlot.attachmentCardBorder: Color(0xFF1D1D21),
      ColorSlot.attachmentPlaceholder: Color(0xFF141416),
      ColorSlot.attachmentTray: Color(0xFF0B0B0C),
      ColorSlot.attachmentChip: Color(0xFF151517),
      ColorSlot.dropOverlay: Color(0xE6050506),
      ColorSlot.dropBorder: Color(0xFFC85E10),

      ColorSlot.voiceConnected: Color(0xFF229E56),
      ColorSlot.voiceConnecting: Color(0xFFC78A02),
      ColorSlot.voiceError: Color(0xFFC72E26),
      ColorSlot.voiceSpeakingRing: Color(0xFFC85E10),
      ColorSlot.voiceMutedIcon: Color(0xFFC72E26),
      ColorSlot.voiceDeafenedIcon: Color(0xFFC72E26),
      ColorSlot.voiceParticipantRow: Color(0x00000000),
      ColorSlot.voiceParticipantRowHover: Color(0xFF161618),
      ColorSlot.voiceControlBar: Color(0xFF060607),
      ColorSlot.voiceControlIcon: Color(0xFF7E7E86),
      ColorSlot.voiceControlIconActive: Color(0xFFC85E10),
      ColorSlot.voiceControlDanger: Color(0xFFC72E26),
      ColorSlot.videoTileBackground: Color(0xFF000000),
      ColorSlot.videoTilePlaceholder: Color(0xFF0B0B0C),
      ColorSlot.volumeSliderTrack: Color(0xFF1F1F23),
      ColorSlot.volumeSliderActive: Color(0xFFC85E10),
    },
    avatarPalette: _avatarRampNight,
  );

  /// For a sunlit desk. Included mainly to prove the theming layer is not
  /// secretly hardcoded for dark surfaces.
  static const day = AppPalette(
    slots: {
      ColorSlot.spaceRail: Color(0xFFD8D6D2),
      ColorSlot.roomSidebar: Color(0xFFE8E6E2),
      ColorSlot.timelineBackground: Color(0xFFF6F4F1),
      ColorSlot.elevatedSurface: Color(0xFFFFFFFF),
      ColorSlot.floatingSurface: Color(0xFFFFFFFF),
      ColorSlot.scrim: Color(0x99000000),

      ColorSlot.messageHover: Color(0xFFEFEDE9),
      ColorSlot.listItemHover: Color(0xFFDEDCD7),
      ColorSlot.listItemSelected: Color(0xFFFBE3CC),
      ColorSlot.railIdle: Color(0xFFEFEDE9),
      ColorSlot.railHover: Color(0xFFC2560A),

      ColorSlot.textPrimary: Color(0xFF23231F),
      ColorSlot.textHeader: Color(0xFF0C0C0A),
      ColorSlot.textMuted: Color(0xFF5C5C56),
      ColorSlot.textFaint: Color(0xFF83837B),
      ColorSlot.textLink: Color(0xFF0A6E9E),
      ColorSlot.textOnAccent: Color(0xFFFFFFFF),

      ColorSlot.accent: Color(0xFFC2560A),
      ColorSlot.accentHover: Color(0xFFA84A08),
      ColorSlot.accentPressed: Color(0xFF8C3D06),
      ColorSlot.danger: Color(0xFFC0261D),
      ColorSlot.success: Color(0xFF1B7A42),
      ColorSlot.warning: Color(0xFF9A6A00),

      ColorSlot.mentionBackground: Color(0xFFFDF0E1),
      ColorSlot.mentionHoverBackground: Color(0xFFFAE5CE),
      ColorSlot.mentionBar: Color(0xFFC2560A),
      ColorSlot.unreadBadge: Color(0xFFC0261D),
      ColorSlot.unreadBadgeText: Color(0xFFFFFFFF),
      ColorSlot.unreadDot: Color(0xFFC2560A),

      ColorSlot.divider: Color(0xFFD5D3CE),
      ColorSlot.dividerStrong: Color(0xFFB6B4AE),
      ColorSlot.scrollbarThumb: Color(0xFFB6B4AE),
      ColorSlot.scrollbarTrack: Color(0xFFE8E6E2),

      ColorSlot.inputBackground: Color(0xFFFFFFFF),
      ColorSlot.inputBackgroundAlt: Color(0xFFFFFFFF),
      ColorSlot.inputBorder: Color(0xFFC7C5BF),
      ColorSlot.inputBorderFocused: Color(0xFFC2560A),

      ColorSlot.attachmentCard: Color(0xFFFFFFFF),
      ColorSlot.attachmentCardBorder: Color(0xFFD5D3CE),
      ColorSlot.attachmentPlaceholder: Color(0xFFE8E6E2),
      ColorSlot.attachmentTray: Color(0xFFEFEDE9),
      ColorSlot.attachmentChip: Color(0xFFFFFFFF),
      ColorSlot.dropOverlay: Color(0xE6F6F4F1),
      ColorSlot.dropBorder: Color(0xFFC2560A),

      ColorSlot.voiceConnected: Color(0xFF1B7A42),
      ColorSlot.voiceConnecting: Color(0xFF9A6A00),
      ColorSlot.voiceError: Color(0xFFC0261D),
      ColorSlot.voiceSpeakingRing: Color(0xFFC2560A),
      ColorSlot.voiceMutedIcon: Color(0xFFC0261D),
      ColorSlot.voiceDeafenedIcon: Color(0xFFC0261D),
      ColorSlot.voiceParticipantRow: Color(0x00000000),
      ColorSlot.voiceParticipantRowHover: Color(0xFFDEDCD7),
      ColorSlot.voiceControlBar: Color(0xFFE8E6E2),
      ColorSlot.voiceControlIcon: Color(0xFF5C5C56),
      ColorSlot.voiceControlIconActive: Color(0xFFC2560A),
      ColorSlot.voiceControlDanger: Color(0xFFC0261D),
      ColorSlot.videoTileBackground: Color(0xFF1A1A1A),
      ColorSlot.videoTilePlaceholder: Color(0xFFD8D6D2),
      ColorSlot.volumeSliderTrack: Color(0xFFC7C5BF),
      ColorSlot.volumeSliderActive: Color(0xFFC2560A),
    },
    avatarPalette: _avatarRampDay,
  );

  /// Instrument colours, used for people with no profile picture. Ordered so
  /// that adjacent entries are far apart in hue — two members of the same room
  /// should not both come out orange.
  static const _avatarRamp = [
    Color(0xFFFF7A18),
    Color(0xFF4FC3F7),
    Color(0xFF2ECC71),
    Color(0xFFFFB302),
    Color(0xFFB388FF),
    Color(0xFFFF3B30),
  ];

  static const _avatarRampNight = [
    Color(0xFFC85E10),
    Color(0xFF3B9BC7),
    Color(0xFF229E56),
    Color(0xFFC78A02),
    Color(0xFF8A68C4),
    Color(0xFFC72E26),
  ];

  static const _avatarRampDay = [
    Color(0xFFC2560A),
    Color(0xFF0A6E9E),
    Color(0xFF1B7A42),
    Color(0xFF9A6A00),
    Color(0xFF6A4BB5),
    Color(0xFFC0261D),
  ];

  static const defaultId = 'hardline_dark';

  static const Map<String, AppPalette> byIdMap = {
    'hardline_dark': dark,
    'hardline_night': night,
    'hardline_day': day,
  };

  /// Display names for the appearance pane.
  static const Map<String, String> labels = {
    'hardline_dark': 'Flight Deck',
    'hardline_night': 'Night Ops',
    'hardline_day': 'Day Panel',
  };

  /// Falls back to [dark] so a stale or hand-edited preference id cannot
  /// prevent the app from starting.
  static AppPalette byId(String id) => byIdMap[id] ?? dark;
}

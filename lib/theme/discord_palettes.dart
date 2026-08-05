import 'package:flutter/material.dart';

import 'discord_colors.dart';

/// The built-in palettes.
///
/// This is the ONLY file in the project that may contain hex color literals.
/// Everywhere else, widgets read roles through `context.colors`. Keeping the
/// values here is what lets a settings screen recolor the whole app later
/// without touching a single widget.
///
/// A palette must define every slot in [DiscordSlot.all]; the theme test
/// asserts this, because a missing slot renders as loud magenta at runtime.
abstract final class DiscordPalettes {
  /// Discord's current (2022+) dark theme. The app default.
  static const dark = DiscordColors(
    slots: {
      DiscordSlot.serverRail: Color(0xFF1E1F22),
      DiscordSlot.channelSidebar: Color(0xFF2B2D31),
      DiscordSlot.chatBackground: Color(0xFF313338),
      DiscordSlot.elevatedSurface: Color(0xFF383A40),
      DiscordSlot.floatingSurface: Color(0xFF111214),
      DiscordSlot.scrim: Color(0xCC000000),

      DiscordSlot.messageHover: Color(0xFF2E3035),
      DiscordSlot.listItemHover: Color(0xFF35373C),
      DiscordSlot.listItemSelected: Color(0xFF404249),
      DiscordSlot.railIdle: Color(0xFF313338),
      DiscordSlot.railHover: Color(0xFF5865F2),

      DiscordSlot.textPrimary: Color(0xFFDBDEE1),
      DiscordSlot.textHeader: Color(0xFFF2F3F5),
      DiscordSlot.textMuted: Color(0xFF949BA4),
      DiscordSlot.textFaint: Color(0xFF80848E),
      DiscordSlot.textLink: Color(0xFF00A8FC),
      DiscordSlot.textOnAccent: Color(0xFFFFFFFF),

      DiscordSlot.accent: Color(0xFF5865F2),
      DiscordSlot.accentHover: Color(0xFF4752C4),
      DiscordSlot.accentPressed: Color(0xFF3C45A5),
      DiscordSlot.danger: Color(0xFFDA373C),
      DiscordSlot.success: Color(0xFF23A55A),
      DiscordSlot.warning: Color(0xFFF0B232),

      DiscordSlot.mentionBackground: Color(0xFF3C3F53),
      DiscordSlot.mentionHoverBackground: Color(0xFF434765),
      DiscordSlot.mentionBar: Color(0xFF5865F2),
      DiscordSlot.unreadBadge: Color(0xFFF23F42),
      DiscordSlot.unreadBadgeText: Color(0xFFFFFFFF),
      DiscordSlot.unreadDot: Color(0xFFFFFFFF),

      DiscordSlot.divider: Color(0xFF3F4147),
      DiscordSlot.dividerStrong: Color(0xFF26282C),
      DiscordSlot.scrollbarThumb: Color(0xFF1A1B1E),
      DiscordSlot.scrollbarTrack: Color(0xFF2B2D31),

      DiscordSlot.inputBackground: Color(0xFF383A40),
      DiscordSlot.inputBackgroundAlt: Color(0xFF1E1F22),
      DiscordSlot.inputBorder: Color(0xFF1E1F22),
      DiscordSlot.inputBorderFocused: Color(0xFF00A8FC),
    },
    avatarPalette: _avatarRamp,
  );

  /// Discord's pre-2022 dark theme — noticeably warmer greys.
  static const darkClassic = DiscordColors(
    slots: {
      DiscordSlot.serverRail: Color(0xFF202225),
      DiscordSlot.channelSidebar: Color(0xFF2F3136),
      DiscordSlot.chatBackground: Color(0xFF36393F),
      DiscordSlot.elevatedSurface: Color(0xFF40444B),
      DiscordSlot.floatingSurface: Color(0xFF18191C),
      DiscordSlot.scrim: Color(0xCC000000),

      DiscordSlot.messageHover: Color(0xFF32353B),
      DiscordSlot.listItemHover: Color(0xFF3A3C43),
      DiscordSlot.listItemSelected: Color(0xFF42464D),
      DiscordSlot.railIdle: Color(0xFF36393F),
      DiscordSlot.railHover: Color(0xFF5865F2),

      DiscordSlot.textPrimary: Color(0xFFDCDDDE),
      DiscordSlot.textHeader: Color(0xFFFFFFFF),
      DiscordSlot.textMuted: Color(0xFF96989D),
      DiscordSlot.textFaint: Color(0xFF72767D),
      DiscordSlot.textLink: Color(0xFF00AFF4),
      DiscordSlot.textOnAccent: Color(0xFFFFFFFF),

      DiscordSlot.accent: Color(0xFF5865F2),
      DiscordSlot.accentHover: Color(0xFF4752C4),
      DiscordSlot.accentPressed: Color(0xFF3C45A5),
      DiscordSlot.danger: Color(0xFFED4245),
      DiscordSlot.success: Color(0xFF3BA55D),
      DiscordSlot.warning: Color(0xFFFAA81A),

      DiscordSlot.mentionBackground: Color(0xFF3E4155),
      DiscordSlot.mentionHoverBackground: Color(0xFF454A66),
      DiscordSlot.mentionBar: Color(0xFF5865F2),
      DiscordSlot.unreadBadge: Color(0xFFED4245),
      DiscordSlot.unreadBadgeText: Color(0xFFFFFFFF),
      DiscordSlot.unreadDot: Color(0xFFFFFFFF),

      DiscordSlot.divider: Color(0xFF42454A),
      DiscordSlot.dividerStrong: Color(0xFF202225),
      DiscordSlot.scrollbarThumb: Color(0xFF202225),
      DiscordSlot.scrollbarTrack: Color(0xFF2F3136),

      DiscordSlot.inputBackground: Color(0xFF40444B),
      DiscordSlot.inputBackgroundAlt: Color(0xFF202225),
      DiscordSlot.inputBorder: Color(0xFF202225),
      DiscordSlot.inputBorderFocused: Color(0xFF00AFF4),
    },
    avatarPalette: _avatarRamp,
  );

  /// Discord's light theme. Included mainly to prove the theming layer is not
  /// secretly hardcoded for dark surfaces.
  static const light = DiscordColors(
    slots: {
      DiscordSlot.serverRail: Color(0xFFE3E5E8),
      DiscordSlot.channelSidebar: Color(0xFFF2F3F5),
      DiscordSlot.chatBackground: Color(0xFFFFFFFF),
      DiscordSlot.elevatedSurface: Color(0xFFEBEDEF),
      DiscordSlot.floatingSurface: Color(0xFFFFFFFF),
      DiscordSlot.scrim: Color(0x99000000),

      DiscordSlot.messageHover: Color(0xFFF7F8F9),
      DiscordSlot.listItemHover: Color(0xFFE0E1E5),
      DiscordSlot.listItemSelected: Color(0xFFD4D7DC),
      DiscordSlot.railIdle: Color(0xFFFFFFFF),
      DiscordSlot.railHover: Color(0xFF5865F2),

      DiscordSlot.textPrimary: Color(0xFF313338),
      DiscordSlot.textHeader: Color(0xFF060607),
      DiscordSlot.textMuted: Color(0xFF5C5E66),
      DiscordSlot.textFaint: Color(0xFF80848E),
      DiscordSlot.textLink: Color(0xFF006CE7),
      DiscordSlot.textOnAccent: Color(0xFFFFFFFF),

      DiscordSlot.accent: Color(0xFF5865F2),
      DiscordSlot.accentHover: Color(0xFF4752C4),
      DiscordSlot.accentPressed: Color(0xFF3C45A5),
      DiscordSlot.danger: Color(0xFFD83C3E),
      DiscordSlot.success: Color(0xFF248046),
      DiscordSlot.warning: Color(0xFFB98300),

      DiscordSlot.mentionBackground: Color(0xFFF0F2FF),
      DiscordSlot.mentionHoverBackground: Color(0xFFE5E9FF),
      DiscordSlot.mentionBar: Color(0xFF5865F2),
      DiscordSlot.unreadBadge: Color(0xFFD83C3E),
      DiscordSlot.unreadBadgeText: Color(0xFFFFFFFF),
      DiscordSlot.unreadDot: Color(0xFF060607),

      DiscordSlot.divider: Color(0xFFE3E5E8),
      DiscordSlot.dividerStrong: Color(0xFFD8D9DC),
      DiscordSlot.scrollbarThumb: Color(0xFFC4C9CE),
      DiscordSlot.scrollbarTrack: Color(0xFFF2F3F5),

      DiscordSlot.inputBackground: Color(0xFFEBEDEF),
      DiscordSlot.inputBackgroundAlt: Color(0xFFFFFFFF),
      DiscordSlot.inputBorder: Color(0xFFDCDEE1),
      DiscordSlot.inputBorderFocused: Color(0xFF006CE7),
    },
    avatarPalette: _avatarRamp,
  );

  /// Discord's avatar accent ramp, used for users with no profile picture.
  static const _avatarRamp = [
    Color(0xFF5865F2),
    Color(0xFF3BA55D),
    Color(0xFFFAA81A),
    Color(0xFFED4245),
    Color(0xFFEB459E),
    Color(0xFF9C84EF),
  ];

  static const defaultId = 'discord_dark';

  static const Map<String, DiscordColors> byIdMap = {
    'discord_dark': dark,
    'discord_dark_classic': darkClassic,
    'discord_light': light,
  };

  /// Display names for a future settings dropdown.
  static const Map<String, String> labels = {
    'discord_dark': 'Dark',
    'discord_dark_classic': 'Dark (Classic)',
    'discord_light': 'Light',
  };

  /// Falls back to [dark] so a stale or hand-edited preference id cannot
  /// prevent the app from starting.
  static DiscordColors byId(String id) => byIdMap[id] ?? dark;
}

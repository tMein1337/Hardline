import 'package:flutter/material.dart';

import 'discord_colors.dart';
import 'discord_spacing.dart';
import 'discord_typography.dart';

/// The only sanctioned way for a widget to obtain a color, metric or text
/// style.
///
/// Widgets must never write `Color(0x…)` or `Colors.*` — those are confined to
/// `discord_palettes.dart`. Going through the theme is what makes the future
/// settings screen able to recolor the entire app without touching widgets.
extension ThemeContextX on BuildContext {
  DiscordColors get colors => Theme.of(this).extension<DiscordColors>()!;
  DiscordMetrics get metrics => Theme.of(this).extension<DiscordMetrics>()!;
  DiscordTypography get text => Theme.of(this).extension<DiscordTypography>()!;
}

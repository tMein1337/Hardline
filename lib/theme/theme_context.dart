// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'color_slots.dart';
import 'metrics.dart';
import 'typography.dart';

/// The only sanctioned way for a widget to obtain a color, metric or text
/// style.
///
/// Widgets must never write `Color(0x…)` or `Colors.*` — those are confined to
/// `palettes.dart`. Going through the theme is what makes the future
/// settings screen able to recolor the entire app without touching widgets.
extension ThemeContextX on BuildContext {
  AppPalette get colors => Theme.of(this).extension<AppPalette>()!;
  AppMetrics get metrics => Theme.of(this).extension<AppMetrics>()!;
  AppTypography get text => Theme.of(this).extension<AppTypography>()!;
}

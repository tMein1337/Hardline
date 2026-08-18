// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'app_theme_state.dart';
import 'color_slots.dart';
import 'metrics.dart';
import 'typography.dart';

/// Builds the [ThemeData] the app renders with.
///
/// The three extensions attached here are what `context.colors`,
/// `context.metrics` and `context.text` resolve against, so swapping the
/// palette recolors every widget without any of them being modified.
///
/// [tooltipDelay] arrives the same way and for the same reason: setting it on
/// `TooltipThemeData` means every `Tooltip` in the app follows the preference
/// without a single one of them naming it.
ThemeData buildThemeData(
  AppPalette colors,
  AppMetrics metrics, {
  Duration tooltipDelay = kDefaultTooltipDelay,
}) {
  final typography = AppTypography.from(colors);
  final brightness = colors.isDark ? Brightness.dark : Brightness.light;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.textOnAccent,
        surface: colors.timelineBackground,
        onSurface: colors.textPrimary,
        error: colors.danger,
        onError: colors.textOnAccent,
        outline: colors.divider,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.timelineBackground,
    canvasColor: colors.timelineBackground,
    dividerColor: colors.divider,
    fontFamily: AppTypography.fontFamily,
    fontFamilyFallback: AppTypography.fontFamilyFallback,

    // No ripples anywhere: hover and press states are drawn explicitly by the
    // widgets that need them, which is what keeps a press reading as a panel
    // switch rather than as a Material surface.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    splashColor: Colors.transparent,

    extensions: <ThemeExtension<dynamic>>[colors, metrics, typography],

    iconTheme: IconThemeData(color: colors.textMuted, size: 20),
    dividerTheme: DividerThemeData(
      color: colors.divider,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(colors.scrollbarThumb),
      trackColor: WidgetStatePropertyAll(colors.scrollbarTrack),
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
      crossAxisMargin: 2,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.floatingSurface,
        borderRadius: BorderRadius.circular(5),
      ),
      textStyle: typography.subtitle.copyWith(
        color: colors.textHeader,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      // Set here rather than on each `Tooltip`, which is what lets the settings
      // slider change every tooltip in the app at once. Flutter's own default
      // is `Duration.zero` — tooltips firing the moment the pointer crosses
      // anything, which in a window this dense is unusable.
      waitDuration: tooltipDelay,
      // Only applies to touch/long-press; a hovered tooltip stays until the
      // pointer leaves. Long enough to finish reading a device id.
      showDuration: const Duration(seconds: 4),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.textHeader,
      selectionColor: colors.accent.withValues(alpha: 0.4),
      selectionHandleColor: colors.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.inputBackgroundAlt,
      hintStyle: typography.inputText.copyWith(color: colors.textFaint),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(metrics.rowRadius),
        borderSide: BorderSide(color: colors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(metrics.rowRadius),
        borderSide: BorderSide(color: colors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(metrics.rowRadius),
        borderSide: BorderSide(color: colors.inputBorderFocused),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(metrics.rowRadius),
        borderSide: BorderSide(color: colors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(metrics.rowRadius),
        borderSide: BorderSide(color: colors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.textOnAccent,
        disabledBackgroundColor: colors.accent.withValues(alpha: 0.5),
        disabledForegroundColor: colors.textOnAccent.withValues(alpha: 0.6),
        textStyle: typography.buttonLabel,
        // Height only. `Size.fromHeight(44)` looks like it says that but is
        // `Size(double.infinity, 44)` — an infinite *minimum width*, which is
        // invisible wherever a bounded width clamps it (a stretched Column, as
        // on the login screen) and fatal wherever nothing does. A Row lays out
        // non-flex children with unbounded main-axis constraints, so a
        // FilledButton in a Row threw "BoxConstraints forces an infinite
        // width", aborting layout for the whole subtree — which renders as a
        // blank pane and a cascade of "render box was not laid out" errors.
        //
        // 64 is Material's own default minimum width.
        minimumSize: const Size(64, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(metrics.rowRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.textLink,
        textStyle: typography.subtitle,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.elevatedSurface,
    ),
  );
}

import 'package:flutter/material.dart';

import 'discord_colors.dart';
import 'discord_spacing.dart';
import 'discord_typography.dart';

/// Builds the [ThemeData] the app renders with.
///
/// The three extensions attached here are what `context.colors`,
/// `context.metrics` and `context.text` resolve against, so swapping the
/// palette recolors every widget without any of them being modified.
ThemeData buildThemeData(DiscordColors colors, DiscordMetrics metrics) {
  final typography = DiscordTypography.from(colors);
  final brightness = colors.isDark ? Brightness.dark : Brightness.light;

  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.textOnAccent,
        surface: colors.chatBackground,
        onSurface: colors.textPrimary,
        error: colors.danger,
        onError: colors.textOnAccent,
        outline: colors.divider,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.chatBackground,
    canvasColor: colors.chatBackground,
    dividerColor: colors.divider,
    fontFamily: DiscordTypography.fontFamily,
    fontFamilyFallback: DiscordTypography.fontFamilyFallback,

    // Discord has no ripples; hover and press states are drawn explicitly by
    // the widgets that need them.
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
      waitDuration: const Duration(milliseconds: 400),
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
        minimumSize: const Size.fromHeight(44),
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

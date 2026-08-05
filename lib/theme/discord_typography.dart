import 'package:flutter/material.dart';

import 'discord_colors.dart';

/// Text styles, pre-colored from the active palette.
///
/// Built by `buildThemeData` via [DiscordTypography.from] so widgets get a
/// ready-to-use style — `context.text.messageBody` already carries the right
/// color, and recolors automatically when the palette changes.
@immutable
class DiscordTypography extends ThemeExtension<DiscordTypography> {
  const DiscordTypography({
    required this.messageBody,
    required this.username,
    required this.timestamp,
    required this.channelName,
    required this.channelNameActive,
    required this.sectionHeader,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.systemEvent,
    required this.inputText,
    required this.buttonLabel,
    required this.fieldLabel,
  });

  /// Discord ships "gg sans"; these are the closest stock Windows faces.
  static const fontFamily = 'Segoe UI';
  static const fontFamilyFallback = ['Segoe UI Variable', 'Roboto', 'Arial'];

  final TextStyle messageBody;
  final TextStyle username;
  final TextStyle timestamp;
  final TextStyle channelName;
  final TextStyle channelNameActive;
  final TextStyle sectionHeader;
  final TextStyle title;
  final TextStyle subtitle;
  final TextStyle badge;
  final TextStyle systemEvent;
  final TextStyle inputText;
  final TextStyle buttonLabel;
  final TextStyle fieldLabel;

  factory DiscordTypography.from(DiscordColors c) {
    const family = fontFamily;
    const fallback = fontFamilyFallback;

    return DiscordTypography(
      messageBody: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 15,
        height: 1.375,
        color: c.textPrimary,
      ),
      username: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 15,
        height: 1.375,
        fontWeight: FontWeight.w500,
        color: c.textHeader,
      ),
      timestamp: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 12,
        color: c.textMuted,
      ),
      channelName: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: c.textMuted,
      ),
      channelNameActive: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: c.textHeader,
      ),
      sectionHeader: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: c.textMuted,
      ),
      title: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.textHeader,
      ),
      subtitle: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 13,
        color: c.textMuted,
      ),
      badge: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1,
        color: c.unreadBadgeText,
      ),
      systemEvent: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 14,
        color: c.textMuted,
      ),
      inputText: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 15,
        height: 1.375,
        color: c.textPrimary,
      ),
      buttonLabel: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: c.textOnAccent,
      ),
      fieldLabel: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: c.textMuted,
      ),
    );
  }

  @override
  DiscordTypography copyWith({
    TextStyle? messageBody,
    TextStyle? username,
    TextStyle? timestamp,
    TextStyle? channelName,
    TextStyle? channelNameActive,
    TextStyle? sectionHeader,
    TextStyle? title,
    TextStyle? subtitle,
    TextStyle? badge,
    TextStyle? systemEvent,
    TextStyle? inputText,
    TextStyle? buttonLabel,
    TextStyle? fieldLabel,
  }) {
    return DiscordTypography(
      messageBody: messageBody ?? this.messageBody,
      username: username ?? this.username,
      timestamp: timestamp ?? this.timestamp,
      channelName: channelName ?? this.channelName,
      channelNameActive: channelNameActive ?? this.channelNameActive,
      sectionHeader: sectionHeader ?? this.sectionHeader,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      badge: badge ?? this.badge,
      systemEvent: systemEvent ?? this.systemEvent,
      inputText: inputText ?? this.inputText,
      buttonLabel: buttonLabel ?? this.buttonLabel,
      fieldLabel: fieldLabel ?? this.fieldLabel,
    );
  }

  @override
  DiscordTypography lerp(covariant DiscordTypography? other, double t) {
    if (other == null) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return DiscordTypography(
      messageBody: l(messageBody, other.messageBody),
      username: l(username, other.username),
      timestamp: l(timestamp, other.timestamp),
      channelName: l(channelName, other.channelName),
      channelNameActive: l(channelNameActive, other.channelNameActive),
      sectionHeader: l(sectionHeader, other.sectionHeader),
      title: l(title, other.title),
      subtitle: l(subtitle, other.subtitle),
      badge: l(badge, other.badge),
      systemEvent: l(systemEvent, other.systemEvent),
      inputText: l(inputText, other.inputText),
      buttonLabel: l(buttonLabel, other.buttonLabel),
      fieldLabel: l(fieldLabel, other.fieldLabel),
    );
  }
}

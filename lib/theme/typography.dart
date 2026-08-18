// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'color_slots.dart';

/// Text styles, pre-colored from the active palette.
///
/// Built by `buildThemeData` via [AppTypography.from] so widgets get a
/// ready-to-use style — `context.text.messageBody` already carries the right
/// color, and recolors automatically when the palette changes.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  const AppTypography({
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

  /// The interface face. Stock Windows, so a release carries no font licences
  /// of its own and nothing has to be embedded.
  static const fontFamily = 'Segoe UI';
  static const fontFamilyFallback = ['Segoe UI Variable', 'Roboto', 'Arial'];

  /// Used wherever a value is *read* rather than prose — timestamps, counts,
  /// device ids. Monospaced digits keep a column of them from shifting as the
  /// numbers change, which is the whole reason instrument readouts are set this
  /// way.
  static const monoFamily = 'Consolas';
  static const monoFamilyFallback = [
    'Cascadia Mono',
    'Consolas',
    'DejaVu Sans Mono',
    'monospace',
  ];

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

  factory AppTypography.from(AppPalette c) {
    const family = fontFamily;
    const fallback = fontFamilyFallback;

    return AppTypography(
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
        fontFamily: monoFamily,
        fontFamilyFallback: monoFamilyFallback,
        fontSize: 11,
        letterSpacing: 0.2,
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
      // Tracked out and set small, the way a panel legend is engraved.
      sectionHeader: TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
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
        fontFamily: monoFamily,
        fontFamilyFallback: monoFamilyFallback,
        fontSize: 11,
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
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: c.textMuted,
      ),
    );
  }

  @override
  AppTypography copyWith({
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
    return AppTypography(
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
  AppTypography lerp(covariant AppTypography? other, double t) {
    if (other == null) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTypography(
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

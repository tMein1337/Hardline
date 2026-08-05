import 'package:flutter/material.dart';

/// Layout constants that define Discord's proportions.
///
/// A [ThemeExtension] rather than plain constants so the same "change it in
/// settings, every widget follows" path that exists for colors also exists for
/// density later (a compact mode, for instance).
@immutable
class DiscordMetrics extends ThemeExtension<DiscordMetrics> {
  const DiscordMetrics({
    required this.railWidth,
    required this.railIconSize,
    required this.sidebarWidth,
    required this.avatarSize,
    required this.avatarGutter,
    required this.messageGroupSpacing,
    required this.messageBlockSpacing,
    required this.headerHeight,
    required this.rowRadius,
    required this.contentPadding,
  });

  /// Width of the leftmost space/server column.
  final double railWidth;

  /// Diameter of a space icon in the rail.
  final double railIconSize;

  /// Width of the room ("channel") list column.
  final double sidebarWidth;

  /// Diameter of a message author avatar.
  final double avatarSize;

  /// Horizontal space between the avatar and the message text. Continuation
  /// lines are inset by `avatarSize + avatarGutter` so text stays aligned.
  final double avatarGutter;

  /// Vertical gap between consecutive messages from the same author.
  final double messageGroupSpacing;

  /// Vertical gap before a message that starts a new author block.
  final double messageBlockSpacing;

  /// Height of the chat and sidebar headers.
  final double headerHeight;

  /// Corner radius for list rows and buttons.
  final double rowRadius;

  /// Horizontal padding inside the chat column.
  final double contentPadding;

  /// Discord's actual desktop proportions.
  static const standard = DiscordMetrics(
    railWidth: 72,
    railIconSize: 48,
    sidebarWidth: 240,
    avatarSize: 40,
    avatarGutter: 16,
    messageGroupSpacing: 2,
    messageBlockSpacing: 17,
    headerHeight: 48,
    rowRadius: 4,
    contentPadding: 16,
  );

  /// Left inset that aligns continuation text with the first line's text.
  double get messageTextInset => avatarSize + avatarGutter;

  @override
  DiscordMetrics copyWith({
    double? railWidth,
    double? railIconSize,
    double? sidebarWidth,
    double? avatarSize,
    double? avatarGutter,
    double? messageGroupSpacing,
    double? messageBlockSpacing,
    double? headerHeight,
    double? rowRadius,
    double? contentPadding,
  }) {
    return DiscordMetrics(
      railWidth: railWidth ?? this.railWidth,
      railIconSize: railIconSize ?? this.railIconSize,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      avatarSize: avatarSize ?? this.avatarSize,
      avatarGutter: avatarGutter ?? this.avatarGutter,
      messageGroupSpacing: messageGroupSpacing ?? this.messageGroupSpacing,
      messageBlockSpacing: messageBlockSpacing ?? this.messageBlockSpacing,
      headerHeight: headerHeight ?? this.headerHeight,
      rowRadius: rowRadius ?? this.rowRadius,
      contentPadding: contentPadding ?? this.contentPadding,
    );
  }

  @override
  DiscordMetrics lerp(covariant DiscordMetrics? other, double t) {
    if (other == null) return this;
    double l(double a, double b) => a + (b - a) * t;
    return DiscordMetrics(
      railWidth: l(railWidth, other.railWidth),
      railIconSize: l(railIconSize, other.railIconSize),
      sidebarWidth: l(sidebarWidth, other.sidebarWidth),
      avatarSize: l(avatarSize, other.avatarSize),
      avatarGutter: l(avatarGutter, other.avatarGutter),
      messageGroupSpacing: l(messageGroupSpacing, other.messageGroupSpacing),
      messageBlockSpacing: l(messageBlockSpacing, other.messageBlockSpacing),
      headerHeight: l(headerHeight, other.headerHeight),
      rowRadius: l(rowRadius, other.rowRadius),
      contentPadding: l(contentPadding, other.contentPadding),
    );
  }
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Layout constants that define Hardline's proportions.
///
/// A [ThemeExtension] rather than plain constants so the same "change it in
/// settings, every widget follows" path that exists for colors also exists for
/// density later (a compact mode, for instance).
@immutable
class AppMetrics extends ThemeExtension<AppMetrics> {
  const AppMetrics({
    required this.railWidth,
    required this.railIconSize,
    required this.railIconRadius,
    required this.railMarkerWidth,
    required this.sidebarWidth,
    required this.avatarSize,
    required this.avatarRadius,
    required this.avatarGutter,
    required this.messageGroupSpacing,
    required this.messageBlockSpacing,
    required this.headerHeight,
    required this.rowRadius,
    required this.contentPadding,
  });

  /// Width of the leftmost space column.
  final double railWidth;

  /// Edge length of a space tile in the rail.
  final double railIconSize;

  /// Corner radius of a space tile. Fixed, not animated: a tile is a panel
  /// button, and it keeps its shape whatever state it is in.
  final double railIconRadius;

  /// Width of the square state marker on the rail's left edge.
  final double railMarkerWidth;

  /// Width of the room list column.
  final double sidebarWidth;

  /// Edge length of a message author avatar.
  final double avatarSize;

  /// Corner radius of an avatar. Rounded rectangles rather than circles, which
  /// is the shape the whole interface is built from.
  final double avatarRadius;

  /// Horizontal space between the avatar and the message text. Continuation
  /// lines are inset by `avatarSize + avatarGutter` so text stays aligned.
  final double avatarGutter;

  /// Vertical gap between consecutive messages from the same author.
  final double messageGroupSpacing;

  /// Vertical gap before a message that starts a new author block.
  final double messageBlockSpacing;

  /// Height of the chat and sidebar headers.
  final double headerHeight;

  /// Corner radius for list rows and buttons. Nearly square: panel hardware has
  /// crisp edges, and this is what keeps rows reading as instrument rows rather
  /// than as cards.
  final double rowRadius;

  /// Horizontal padding inside the chat column.
  final double contentPadding;

  /// The shipped density.
  ///
  /// Chosen for a 1280-wide window with the message column carrying roughly 90
  /// characters at the default text size: a narrow rail because it holds tiles
  /// rather than portraits, a wide room list because Matrix room names are
  /// long, and tight vertical rhythm so more of the timeline is on screen.
  static const standard = AppMetrics(
    railWidth: 64,
    railIconSize: 40,
    railIconRadius: 8,
    railMarkerWidth: 3,
    sidebarWidth: 256,
    avatarSize: 34,
    avatarRadius: 10,
    avatarGutter: 14,
    messageGroupSpacing: 3,
    messageBlockSpacing: 12,
    headerHeight: 40,
    rowRadius: 2,
    contentPadding: 20,
  );

  /// Left inset that aligns continuation text with the first line's text.
  double get messageTextInset => avatarSize + avatarGutter;

  @override
  AppMetrics copyWith({
    double? railWidth,
    double? railIconSize,
    double? railIconRadius,
    double? railMarkerWidth,
    double? sidebarWidth,
    double? avatarSize,
    double? avatarRadius,
    double? avatarGutter,
    double? messageGroupSpacing,
    double? messageBlockSpacing,
    double? headerHeight,
    double? rowRadius,
    double? contentPadding,
  }) {
    return AppMetrics(
      railWidth: railWidth ?? this.railWidth,
      railIconSize: railIconSize ?? this.railIconSize,
      railIconRadius: railIconRadius ?? this.railIconRadius,
      railMarkerWidth: railMarkerWidth ?? this.railMarkerWidth,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      avatarSize: avatarSize ?? this.avatarSize,
      avatarRadius: avatarRadius ?? this.avatarRadius,
      avatarGutter: avatarGutter ?? this.avatarGutter,
      messageGroupSpacing: messageGroupSpacing ?? this.messageGroupSpacing,
      messageBlockSpacing: messageBlockSpacing ?? this.messageBlockSpacing,
      headerHeight: headerHeight ?? this.headerHeight,
      rowRadius: rowRadius ?? this.rowRadius,
      contentPadding: contentPadding ?? this.contentPadding,
    );
  }

  @override
  AppMetrics lerp(covariant AppMetrics? other, double t) {
    if (other == null) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppMetrics(
      railWidth: l(railWidth, other.railWidth),
      railIconSize: l(railIconSize, other.railIconSize),
      railIconRadius: l(railIconRadius, other.railIconRadius),
      railMarkerWidth: l(railMarkerWidth, other.railMarkerWidth),
      sidebarWidth: l(sidebarWidth, other.sidebarWidth),
      avatarSize: l(avatarSize, other.avatarSize),
      avatarRadius: l(avatarRadius, other.avatarRadius),
      avatarGutter: l(avatarGutter, other.avatarGutter),
      messageGroupSpacing: l(messageGroupSpacing, other.messageGroupSpacing),
      messageBlockSpacing: l(messageBlockSpacing, other.messageBlockSpacing),
      headerHeight: l(headerHeight, other.headerHeight),
      rowRadius: l(rowRadius, other.rowRadius),
      contentPadding: l(contentPadding, other.contentPadding),
    );
  }
}

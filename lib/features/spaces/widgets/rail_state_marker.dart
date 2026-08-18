// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// The state marker on the left edge of the rail.
///
/// A square-cut bar, sized in three steps rather than animated smoothly: full
/// height when the space is selected, a short segment on hover, and a single
/// square notch when the space has something unread. Reading the rail edge
/// alone should tell you where you are and where something is waiting.
///
/// Colour carries the same meaning as everywhere else — the accent for "this is
/// the one you are on", the unread colour for "look here".
class RailStateMarker extends StatelessWidget {
  const RailStateMarker({
    super.key,
    required this.selected,
    required this.hovered,
    required this.hasUnread,
    required this.tileHeight,
  });

  final bool selected;
  final bool hovered;
  final bool hasUnread;

  /// Height of the space tile this marker sits beside. The selected marker
  /// matches it exactly, so the two read as one bracketed unit.
  final double tileHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width = context.metrics.railMarkerWidth;

    final (height, color) = switch ((selected, hovered, hasUnread)) {
      (true, _, _) => (tileHeight, colors.accent),
      (_, true, _) => (tileHeight * 0.4, colors.textMuted),
      (_, _, true) => (width, colors.unreadDot),
      _ => (0.0, colors.unreadDot),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.linear,
      width: width,
      height: height,
      // Square: the marker is a segment of the panel edge, not a lozenge.
      color: color,
    );
  }
}

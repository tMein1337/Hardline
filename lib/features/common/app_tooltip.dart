// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Which side of its target an [AppTooltip] opens on.
enum TooltipSide { below, above, right }

/// A [Tooltip] placed against the edge of what it describes, never over it.
///
/// Flutter's own placement measures from the target's centre: the tooltip
/// starts `verticalOffset` (24px) below the middle of whatever it is attached
/// to. For an icon button that lands just under the button. For anything
/// taller than 48px — a rail tile, a two-line row — it lands on top of the
/// very thing the pointer is resting on, which is what made the rail's tooltip
/// cover the space it named. Measuring from the edge instead keeps the same
/// small gap whatever the size of the target.
///
/// Still a [Tooltip] underneath, so the styling and the delay setting come
/// from the theme as before, and `find.byTooltip` keeps finding it.
///
/// [side] is a preference: when there is no room there, the tooltip opens on
/// the opposite side, and it is always kept [_screenMargin] inside the window.
class AppTooltip extends StatelessWidget {
  const AppTooltip({
    super.key,
    this.message,
    this.richMessage,
    this.side = TooltipSide.below,
    required this.child,
  }) : assert(
         (message == null) != (richMessage == null),
         'Exactly one of message and richMessage',
       );

  final String? message;
  final InlineSpan? richMessage;
  final TooltipSide side;
  final Widget child;

  /// Space between the target's edge and the tooltip.
  static const double gap = 6;
  static const double _screenMargin = 8;

  /// The placement [AppTooltip] uses, for a [Tooltip] that has to be built
  /// directly.
  static Offset position(TooltipPositionContext context, TooltipSide side) {
    final target = context.target;
    final half = context.targetSize / 2;
    final tooltip = context.tooltipSize;
    final overlay = context.overlaySize;

    double clamp(double value, double size, double extent) {
      final max = extent - size - _screenMargin;
      return max < _screenMargin
          ? _screenMargin
          : value.clamp(_screenMargin, max);
    }

    if (side == TooltipSide.right) {
      var x = target.dx + half.width + gap;
      if (x + tooltip.width > overlay.width - _screenMargin) {
        x = target.dx - half.width - gap - tooltip.width;
      }
      return Offset(
        clamp(x, tooltip.width, overlay.width),
        clamp(target.dy - tooltip.height / 2, tooltip.height, overlay.height),
      );
    }

    final below = target.dy + half.height + gap;
    final above = target.dy - half.height - gap - tooltip.height;
    final fitsBelow = below + tooltip.height <= overlay.height - _screenMargin;
    final fitsAbove = above >= _screenMargin;
    final y = switch (side) {
      TooltipSide.below => fitsBelow || !fitsAbove ? below : above,
      _ => fitsAbove || !fitsBelow ? above : below,
    };
    return Offset(
      clamp(target.dx - tooltip.width / 2, tooltip.width, overlay.width),
      y,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      richMessage: richMessage,
      positionDelegate: (context) => position(context, side),
      child: child,
    );
  }
}

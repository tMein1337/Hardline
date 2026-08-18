// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../../common/unread_badge.dart';
import '../space_summary.dart';
import 'rail_state_marker.dart';

/// One space in the left rail.
///
/// The tile keeps one shape in every state — a rounded square, the same shape
/// avatars and rows use elsewhere. State is signalled by what is drawn *around*
/// it instead: corner brackets when selected, a thin outline on hover, and the
/// edge marker to its left. Nothing about the tile itself moves, which is what
/// keeps a column of them reading as a fixed row of panel buttons.
class SpaceRailButton extends StatelessWidget {
  const SpaceRailButton({
    super.key,
    required this.space,
    required this.selected,
    required this.onTap,
  });

  final SpaceSummary space;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final metrics = context.metrics;
    final size = metrics.railIconSize;
    final radius = BorderRadius.circular(metrics.railIconRadius);

    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) {
        return SizedBox(
          height: size + 10,
          child: Row(
            children: [
              SizedBox(
                width: 7,
                child: Center(
                  child: RailStateMarker(
                    selected: selected,
                    hovered: hovered,
                    hasUnread: space.hasUnread,
                    tileHeight: size,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Tooltip(
                    message: space.name,
                    preferBelow: false,
                    verticalOffset: 0,
                    margin: const EdgeInsets.only(left: 8),
                    child: CustomPaint(
                      // Brackets are painted outside the tile's own box, in the
                      // 5px the rail leaves around it.
                      foregroundPainter: selected
                          ? _CornerBrackets(color: colors.accent)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                color: space.avatarMxc == null
                                    ? (selected
                                          ? colors.accent
                                          : colors.railIdle)
                                    : null,
                                borderRadius: radius,
                                border: hovered && !selected
                                    ? Border.all(
                                        color: colors.accent.withValues(
                                          alpha: 0.55,
                                        ),
                                      )
                                    : null,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: space.isHome
                                  ? Icon(
                                      Icons.grid_view_rounded,
                                      size: size * 0.5,
                                      color: selected
                                          ? colors.textOnAccent
                                          : colors.textPrimary,
                                    )
                                  : MxAvatar(
                                      name: space.name,
                                      seed: space.id,
                                      mxcUri: space.avatarMxc,
                                      size: size,
                                      borderRadius: radius,
                                    ),
                            ),
                            if (space.hasMention)
                              Positioned(
                                right: -4,
                                top: -4,
                                child: UnreadBadge(
                                  count: space.highlightCount,
                                  borderColor: colors.spaceRail,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
          ),
        );
      },
    );
  }
}

/// Four L-shaped ticks at the corners of the tile, the way a display brackets
/// the item it has locked onto.
///
/// Deliberately not a full border: the gap along each edge is what stops it
/// reading as a box and keeps the tile itself the thing being looked at.
class _CornerBrackets extends CustomPainter {
  const _CornerBrackets({required this.color});

  final Color color;

  /// How far each arm runs from its corner.
  static const _arm = 7.0;
  static const _stroke = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    // Inset by half the stroke so the line sits fully inside the painted box.
    final i = _stroke / 2;
    final w = size.width - i;
    final h = size.height - i;

    final path = Path()
      // Top-left.
      ..moveTo(i, i + _arm)
      ..lineTo(i, i)
      ..lineTo(i + _arm, i)
      // Top-right.
      ..moveTo(w - _arm, i)
      ..lineTo(w, i)
      ..lineTo(w, i + _arm)
      // Bottom-right.
      ..moveTo(w, h - _arm)
      ..lineTo(w, h)
      ..lineTo(w - _arm, h)
      // Bottom-left.
      ..moveTo(i + _arm, h)
      ..lineTo(i, h)
      ..lineTo(i, h - _arm);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerBrackets old) => old.color != color;
}

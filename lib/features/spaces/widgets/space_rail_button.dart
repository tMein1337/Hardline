import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../../common/unread_badge.dart';
import '../space_summary.dart';
import 'selection_pill.dart';

/// One icon in the left rail.
///
/// Reproduces Discord's rounded-square-to-circle morph: idle icons are
/// squircles, and hovering or selecting animates them to a full circle.
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

    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) {
        final round = hovered || selected;

        return SizedBox(
          height: size + 8,
          child: Row(
            children: [
              SizedBox(
                width: 8,
                child: Center(
                  child: SelectionPill(
                    selected: selected,
                    hovered: hovered,
                    hasUnread: space.hasUnread,
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.easeOut,
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: space.avatarMxc == null
                                ? (round ? colors.accent : colors.railIdle)
                                : null,
                            borderRadius: BorderRadius.circular(
                              round ? size / 2 : size / 3,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: space.isHome
                              ? Icon(
                                  Icons.home_rounded,
                                  size: size * 0.55,
                                  color: round
                                      ? colors.textOnAccent
                                      : colors.textPrimary,
                                )
                              : MxAvatar(
                                  name: space.name,
                                  seed: space.id,
                                  mxcUri: space.avatarMxc,
                                  size: size,
                                  borderRadius: BorderRadius.circular(
                                    round ? size / 2 : size / 3,
                                  ),
                                ),
                        ),
                        if (space.hasMention)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: UnreadBadge(
                              count: space.highlightCount,
                              borderColor: colors.serverRail,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        );
      },
    );
  }
}

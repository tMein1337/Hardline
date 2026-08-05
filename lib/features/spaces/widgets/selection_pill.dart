import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// The white marker on the left edge of the rail.
///
/// Discord animates its height to signal state: absent when idle, a short stub
/// on hover, a tall bar when selected.
class SelectionPill extends StatelessWidget {
  const SelectionPill({
    super.key,
    required this.selected,
    required this.hovered,
    required this.hasUnread,
  });

  final bool selected;
  final bool hovered;
  final bool hasUnread;

  double get _height {
    if (selected) return 40;
    if (hovered) return 20;
    if (hasUnread) return 8;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      width: 4,
      height: _height,
      decoration: BoxDecoration(
        color: context.colors.unreadDot,
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(4),
        ),
      ),
    );
  }
}

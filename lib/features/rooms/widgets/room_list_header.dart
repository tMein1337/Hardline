import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// Title bar of the channel column, showing the selected space's name.
class RoomListHeader extends StatelessWidget {
  const RoomListHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: context.metrics.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.dividerStrong)),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: context.text.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

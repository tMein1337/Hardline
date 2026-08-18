// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';

/// The red pill showing a mention or notification count.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, this.borderColor});

  final int count;

  /// Drawn as a ring around the badge so it reads clearly when overlapping an
  /// avatar or rail icon.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final colors = context.colors;
    final label = count > 99 ? '99+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: colors.unreadBadge,
        borderRadius: BorderRadius.circular(8),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(label, style: context.text.badge),
    );
  }
}

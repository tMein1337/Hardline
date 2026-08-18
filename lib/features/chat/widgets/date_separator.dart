// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../core/util/time_format.dart';
import '../../../theme/theme_context.dart';

/// Horizontal rule with the date centred on it, between calendar days.
class DateSeparator extends StatelessWidget {
  const DateSeparator({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.metrics.contentPadding,
        vertical: 16,
      ),
      child: Row(
        children: [
          Expanded(child: Divider(color: colors.divider, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              formatDateSeparator(date.toLocal()),
              style: context.text.timestamp.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: colors.divider, height: 1)),
        ],
      ),
    );
  }
}

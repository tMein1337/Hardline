// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// Hairline separator between the shell's columns.
class ShellDivider extends StatelessWidget {
  const ShellDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: context.colors.dividerStrong);
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../shell/selection_providers.dart';
import 'space_list_provider.dart';
import 'widgets/space_rail_button.dart';

/// The leftmost column: Home, then one icon per joined space.
class SpaceRail extends ConsumerWidget {
  const SpaceRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final metrics = context.metrics;
    final spaces = ref.watch(spaceListProvider);
    final selectedId = ref.watch(selectedSpaceIdProvider);

    return Container(
      width: metrics.railWidth,
      color: colors.spaceRail,
      child: ScrollConfiguration(
        // The rail is narrow; a scrollbar here would crowd the icons.
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: spaces.length,
          separatorBuilder: (context, index) {
            // Home is separated from real spaces by a rule.
            if (index != 0) return const SizedBox(height: 8);
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              child: Divider(color: colors.dividerStrong, height: 2),
            );
          },
          itemBuilder: (context, index) {
            final space = spaces[index];
            return SpaceRailButton(
              space: space,
              selected: space.id == selectedId,
              onTap: () => ref
                  .read(selectedSpaceIdProvider.notifier)
                  .select(space.id),
            );
          },
        ),
      ),
    );
  }
}

// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../call_controller_provider.dart';
import '../call_view_provider.dart';

/// Switches the chat column between this room's call and its timeline.
///
/// Renders nothing at all unless we are in *this* room's call, so a text-only
/// room's header is exactly what it was before voice existed.
///
/// Two labelled buttons rather than one icon that changes meaning: the pair
/// says what the alternative is without being clicked, which a single toggle
/// cannot. The chat side carries the room's `#` glyph so the two read as the
/// two halves of the same column rather than as unrelated controls.
class CallViewToggle extends ConsumerWidget {
  const CallViewToggle({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(callControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isInCallFor(roomId)) return const SizedBox.shrink();

        final timeline = ref.watch(timelinePreferredProvider);
        final mode = ref.read(timelinePreferredProvider.notifier);

        return Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Segment(
                icon: Icons.grid_view,
                label: 'Call',
                selected: !timeline,
                onPressed: mode.showCall,
              ),
              const SizedBox(width: 4),
              _Segment(
                icon: Icons.tag,
                label: 'Chat',
                selected: timeline,
                onPressed: mode.showTimeline,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Material(
      color: selected ? colors.listItemSelected : Colors.transparent,
      borderRadius: BorderRadius.circular(context.metrics.rowRadius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(context.metrics.rowRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? colors.accent : colors.textFaint,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: context.text.subtitle.copyWith(
                  color: selected ? colors.textPrimary : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

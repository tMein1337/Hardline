// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/util/display_name.dart';
import '../../../theme/theme_context.dart';
import '../../common/app_tooltip.dart';
import '../../common/hoverable.dart';
import '../reactions.dart';
import '../timeline_provider.dart';
import 'reaction_picker.dart';

/// Asks for a reaction beside the widget at [context] and sends it.
Future<void> pickAndReact(
  BuildContext context,
  WidgetRef ref,
  Event original,
) async {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  // Read before the picker opens: the hover bar that asked disappears as soon
  // as the pointer leaves it, and its `ref` with it.
  final controller = ref.read(timelineControllerProvider(original.roomId!));

  final key = await showReactionPicker(context, anchor: anchor);
  if (key == null) return;
  await controller.react(original, key);
}

/// The reactions under a message, as one chip per emoji.
///
/// Clicking a chip adds our reaction or takes it back; hovering says who
/// reacted. The trailing button opens the picker.
class ReactionRow extends ConsumerWidget {
  const ReactionRow({
    super.key,
    required this.original,
    required this.reactions,
  });

  final Event original;
  final List<ReactionSummary> reactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(timelineControllerProvider(original.roomId!));

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final reaction in reactions)
            _ReactionChip(
              key: ValueKey('reaction_${reaction.key}'),
              reaction: reaction,
              names: _names(reaction.senderIds),
              onTap: () =>
                  unawaited(controller.toggleReaction(original, reaction)),
            ),
          Builder(
            builder: (context) => _AddChip(
              onTap: () => unawaited(pickAndReact(context, ref, original)),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _names(List<String> ids) => [
    for (final id in ids)
      id == original.room.client.userID
          ? 'You'
          : displaySafeName(
              original.room
                  .unsafeGetUserFromMemoryOrFallback(id)
                  .calcDisplayname(),
              fallback: id,
            ),
  ];
}

/// "Alice, Bob and 3 others reacted with 👍".
@visibleForTesting
String describeReaction(List<String> names, String key) {
  const shown = 5;
  final who = switch (names.length) {
    0 => 'Nobody',
    1 => names.single,
    _ when names.length <= shown =>
      '${names.take(names.length - 1).join(', ')} and ${names.last}',
    _ =>
      '${names.take(shown).join(', ')} and ${names.length - shown} '
          '${names.length - shown == 1 ? 'other' : 'others'}',
  };
  return '$who reacted with $key';
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    super.key,
    required this.reaction,
    required this.names,
    required this.onTap,
  });

  final ReactionSummary reaction;
  final List<String> names;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mine = reaction.mine;

    return AppTooltip(
      message: describeReaction(names, reaction.key),
      side: TooltipSide.above,
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: mine
                ? colors.accent.withValues(alpha: hovered ? 0.26 : 0.16)
                : (hovered ? colors.listItemHover : colors.inputBackground),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: mine ? colors.accent : colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  reaction.key,
                  style: context.text.messageBody.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${reaction.count}',
                style: context.text.timestamp.copyWith(
                  color: mine ? colors.textHeader : colors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: 'Add reaction',
      side: TooltipSide.above,
      child: Hoverable(
        onTap: onTap,
        builder: (context, hovered) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: hovered ? colors.listItemHover : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.divider),
          ),
          child: Icon(
            Icons.add_reaction_outlined,
            size: 16,
            color: colors.textMuted,
          ),
        ),
      ),
    );
  }
}

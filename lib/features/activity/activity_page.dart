import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/theme_context.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
import 'activity_prefs_controller.dart';
import 'activity_providers.dart';
import 'message_activity_log.dart';
import 'widgets/activity_section.dart';
import 'widgets/following_manager.dart';
import 'widgets/message_activity_row.dart';
import 'widgets/user_activity_row.dart';
import 'widgets/voice_activity_row.dart';

/// Where the people you follow are, right now.
///
/// Fills the chat column when Home is selected and no room is open — the spot
/// that otherwise shows "No room selected", which is the least useful thing the
/// app can say while it knows perfectly well that three of your colleagues are
/// in a call.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key});

  /// Keeps the page readable on a maximised window without stretching rows to
  /// the full width, the same bound `SettingsPane` uses.
  static const _maxContentWidth = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefs = ref.watch(activityPrefsProvider);

    return Container(
      color: colors.chatBackground,
      child: Column(
        children: [
          const _Header(),
          Expanded(
            child: prefs.hasFollowing
                ? const _Sections()
                : const _NobodyFollowed(),
          ),
        ],
      ),
    );
  }
}

/// Matches `ChatHeader`'s height and rule, so switching between a channel and
/// this page does not shift the content below by a pixel.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final backfill = ref.watch(
      messageActivityLogProvider.select((state) => state.backfill),
    );

    return Container(
      height: context.metrics.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.chatBackground,
        border: Border(bottom: BorderSide(color: colors.dividerStrong)),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt, size: 22, color: colors.textFaint),
          const SizedBox(width: 8),
          Text('Activity', style: context.text.title),
          const SizedBox(width: 12),
          // Without this, a page still filling in is indistinguishable from a
          // page with nothing to show.
          if (backfill.isRunning)
            Flexible(
              child: Text(
                'Catching up… ${backfill.done} of ${backfill.total} rooms',
                style: context.text.timestamp,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Activity settings',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: colors.textMuted,
            onPressed: () => SettingsScreen.open(
              context,
              section: SettingsSection.activity,
            ),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(activityPrefsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ActivityPage._maxContentWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (prefs.showVoice) const _VoiceSection(),
              if (prefs.showActive) const _ActiveSection(),
              if (prefs.showMessages) const _MessagesSection(),
              const FollowingManager(),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceSection extends ConsumerWidget {
  const _VoiceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(followedVoiceActivityProvider);

    return ActivitySection(
      title: 'In voice',
      icon: Icons.headset_mic,
      emptyLabel: 'Nobody you follow is in a call.',
      children: [
        for (final entry in entries.items)
          VoiceActivityRow(
            key: ValueKey('${entry.userId}|${entry.roomId}'),
            activity: entry,
          ),
      ],
    );
  }
}

class _ActiveSection extends ConsumerWidget {
  const _ActiveSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(followedActiveUsersProvider);
    final window = ref.watch(activityPrefsProvider).recentWindow;

    return ActivitySection(
      title: 'Recently active',
      icon: Icons.keyboard,
      emptyLabel:
          'Nobody you follow has typed in the last ${_describe(window)}.',
      children: [
        for (final entry in entries.items)
          UserActivityRow(key: ValueKey(entry.userId), activity: entry),
      ],
    );
  }
}

class _MessagesSection extends ConsumerWidget {
  const _MessagesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(followedMessagesProvider);
    final window = ref.watch(activityPrefsProvider).recentWindow;

    return ActivitySection(
      title: 'Recent messages',
      icon: Icons.forum_outlined,
      emptyLabel: 'Nothing said in the last ${_describe(window)}.',
      children: [
        for (final entry in entries.items)
          MessageActivityRow(key: ValueKey(entry.eventId), activity: entry),
      ],
    );
  }
}

/// The explainer that stands in for four empty headings.
class _NobodyFollowed extends StatelessWidget {
  const _NobodyFollowed();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, size: 56, color: colors.textFaint),
            const SizedBox(height: 16),
            Text('Nobody followed yet', style: context.text.title),
            const SizedBox(height: 6),
            Text(
              'Follow someone and this page shows when they join a call or '
              'say something — in any room, without opening it.\n\n'
              'You can also right-click anyone in a chat or a voice channel.',
              textAlign: TextAlign.center,
              style: context.text.subtitle,
            ),
            const SizedBox(height: 20),
            const AddPeopleButton(),
          ],
        ),
      ),
    );
  }
}

/// "30 minutes", "3 hours" — for the empty lines, which read better with the
/// window spelled out than with a bare number.
String _describe(Duration window) {
  if (window.inMinutes < 60) {
    final minutes = window.inMinutes;
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }
  final hours = window.inHours;
  return '$hours hour${hours == 1 ? '' : 's'}';
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../activity/activity_prefs_controller.dart';
import '../../activity/activity_prefs_state.dart';
import '../../activity/message_activity_log.dart';
import '../../activity/widgets/following_manager.dart';
import '../widgets/settings_layout.dart';

/// What the Home screen's activity summary watches, and how far back it looks.
class ActivityPane extends ConsumerWidget {
  const ActivityPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(activityPrefsProvider);
    final controller = ref.read(activityPrefsProvider.notifier);

    return SettingsPane(
      title: 'Activity',
      description:
          'The summary on the Home screen, showing where the people you follow '
          'are. Nothing here is sent anywhere — following someone is a note to '
          'yourself, and they are never told.',
      children: [
        const SettingsLabel('What to show'),
        SettingsCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              _Toggle(
                value: prefs.showVoice,
                title: 'People in voice channels',
                subtitle:
                    'Who is in a call right now, in any room — including rooms '
                    'you have never opened.',
                onChanged: controller.setShowVoice,
              ),
              _Toggle(
                value: prefs.showActive,
                title: 'People typing or recently active',
                subtitle:
                    'Shows a live "typing…" badge, and otherwise how long ago '
                    'they last said something.',
                onChanged: controller.setShowActive,
              ),
              _Toggle(
                value: prefs.showMessages,
                title: 'Recent messages',
                subtitle:
                    'The messages themselves, newest first. Clicking one opens '
                    'its channel and scrolls to it.',
                onChanged: controller.setShowMessages,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SettingsLabel('How far back "recent" reaches'),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsChoice<Duration>(
                values: kRecentWindowChoices,
                selected: _nearestChoice(prefs.recentWindow),
                labelOf: _labelOf,
                onChanged: controller.setRecentWindow,
              ),
              const SizedBox(height: 10),
              Text(
                'Applies to both the "recently active" list and the message '
                'feed. Widening it takes effect immediately, up to the 24 '
                'hours the app keeps.',
                style: context.text.timestamp,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SettingsLabel('History'),
        const _HistoryCard(),
        const SizedBox(height: 24),
        SettingsLabel('Following · ${prefs.following.length}'),
        const SettingsCard(child: FollowingManager(showHeader: false)),
      ],
    );
  }

  /// A stored window that is not one of the offered steps — hand-edited, or
  /// left over from a build with different choices — still has to select
  /// something, or the row would render with nothing highlighted.
  static Duration _nearestChoice(Duration window) {
    var best = kRecentWindowChoices.first;
    for (final choice in kRecentWindowChoices) {
      final delta = (choice - window).abs();
      if (delta < (best - window).abs()) best = choice;
    }
    return best;
  }

  static String _labelOf(Duration window) => window.inMinutes < 60
      ? '${window.inMinutes} min'
      : '${window.inHours} h';
}

/// The opt-in start-up fetch, and the button that runs it now.
///
/// Both live in one card because they are the same operation: the switch says
/// "do this every launch", the button says "do it once".
class _HistoryCard extends ConsumerWidget {
  const _HistoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(activityPrefsProvider);
    final backfill = ref.watch(
      messageActivityLogProvider.select((state) => state.backfill),
    );

    return SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.backfillOnLaunch,
            title: Text(
              'Fetch history when the app starts',
              style: context.text.messageBody,
            ),
            subtitle: Text(
              'Without this the summary only knows what has arrived since the '
              'app opened, plus the newest message in each room, and fills in '
              'as you use it. With it, the app asks the server for each room\'s '
              'recent history on start-up — complete immediately, at the cost '
              'of a few seconds and one request per room.',
              style: context.text.timestamp,
            ),
            onChanged: (value) async {
              await ref
                  .read(activityPrefsProvider.notifier)
                  .setBackfillOnLaunch(value);
              // Switching it on takes effect now rather than at next launch:
              // being told to wait for a restart is a poor answer to "why is
              // this list empty".
              if (value) {
                await ref.read(messageActivityLogProvider.notifier).backfillNow();
              }
            },
          ),
          const SettingsDivider(),
          Row(
            children: [
              Expanded(child: _StatusLine(backfill: backfill)),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: backfill.isRunning || !prefs.hasFollowing
                    ? null
                    : () => ref
                          .read(messageActivityLogProvider.notifier)
                          .backfillNow(),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Catch up now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.backfill});

  final BackfillProgress backfill;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (text, color) = switch (backfill.phase) {
      BackfillPhase.idle => ('Not run yet this session.', colors.textMuted),
      BackfillPhase.running => (
        'Catching up… ${backfill.done} of ${backfill.total} rooms.',
        colors.textMuted,
      ),
      BackfillPhase.done => (
        'Caught up on ${backfill.total} rooms, '
            '${backfill.fetched} message${backfill.fetched == 1 ? '' : 's'} '
            'added.',
        colors.success,
      ),
      BackfillPhase.failed => (
        'Could not finish: ${backfill.error ?? 'unknown error'}',
        colors.voiceError,
      ),
    };

    return Text(text, style: context.text.timestamp.copyWith(color: color));
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
    value: value,
    title: Text(title, style: context.text.messageBody),
    subtitle: Text(subtitle, style: context.text.timestamp),
    onChanged: onChanged,
  );
}

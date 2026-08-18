// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../activity_entries.dart';
import '../activity_prefs_controller.dart';
import '../activity_providers.dart';
import 'activity_section.dart';

/// Who you follow, with a way to change it.
///
/// Used whole by both the activity page and the settings pane, so the two can
/// never drift into offering different things — which is the failure mode of
/// having a manage list in two places.
class FollowingManager extends ConsumerWidget {
  const FollowingManager({super.key, this.showHeader = true});

  /// The settings pane supplies its own heading, the activity page does not.
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followingProvider);

    final rows = [
      for (final person in following.items)
        _FollowingRow(key: ValueKey(person.userId), person: person),
    ];

    if (!showHeader) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: AddPeopleButton(),
          ),
        ],
      );
    }

    return ActivitySection(
      title: 'Following · ${following.length}',
      icon: Icons.person_add_alt,
      emptyLabel: 'Nobody yet.',
      trailing: const AddPeopleButton(),
      children: rows,
    );
  }
}

/// Opens the picker.
class AddPeopleButton extends ConsumerWidget {
  const AddPeopleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => FollowPickerDialog.show(context),
      icon: const Icon(Icons.add, size: 16),
      label: const Text('Add people'),
    );
  }
}

class _FollowingRow extends ConsumerWidget {
  const _FollowingRow({super.key, required this.person});

  final FollowCandidate person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return ActivityRow(
      avatar: MxAvatar(
        name: person.displayName,
        seed: person.userId,
        mxcUri: person.avatarMxc,
        size: 28,
      ),
      title: Text(person.displayName),
      subtitle: Text(person.userId),
      trailing: IconButton(
        tooltip: 'Unfollow',
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        color: colors.textMuted,
        onPressed: () =>
            ref.read(activityPrefsProvider.notifier).unfollow(person.userId),
        icon: const Icon(Icons.close),
      ),
    );
  }
}

/// Picks somebody to follow out of everyone in your joined rooms.
///
/// The candidate list is the SDK's in-memory member lists, which is why it is
/// synchronous and why it can be short: Matrix loads members lazily, so a room
/// whose timeline has never been opened contributes only the people the sync
/// happened to mention. Typing a full user id always works regardless.
class FollowPickerDialog extends ConsumerStatefulWidget {
  const FollowPickerDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog(
    context: context,
    builder: (context) => const FollowPickerDialog(),
  );

  @override
  ConsumerState<FollowPickerDialog> createState() => _FollowPickerDialogState();
}

class _FollowPickerDialogState extends ConsumerState<FollowPickerDialog> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A typed-out Matrix id that is not in any room we know about.
  ///
  /// Worth offering: somebody you share no *loaded* room with is exactly the
  /// person the in-memory member lists cannot suggest, and following them is
  /// harmless — they simply never show activity until they say something
  /// somewhere you can see.
  String? get _literalId {
    final text = _query.trim();
    if (!text.startsWith('@') || !text.contains(':')) return null;
    if (text.length < 4) return null;
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final candidates = ref.watch(followCandidatesProvider);
    final query = _query.trim().toLowerCase();

    final matches = [
      for (final person in candidates.items)
        if (query.isEmpty ||
            person.displayName.toLowerCase().contains(query) ||
            person.userId.toLowerCase().contains(query))
          person,
    ];

    final literal = _literalId;
    final showLiteral =
        literal != null && !matches.any((p) => p.userId == literal);

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Follow someone', style: context.text.title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: context.text.inputText,
              decoration: const InputDecoration(
                hintText: 'Search a name, or type @user:server',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty && !showLiteral
                  ? Center(
                      child: Text(
                        candidates.isEmpty
                            ? 'Nobody left to follow in the rooms you have '
                                  'open.'
                            : 'No match.',
                        textAlign: TextAlign.center,
                        style: context.text.subtitle,
                      ),
                    )
                  : ListView(
                      children: [
                        if (showLiteral)
                          _CandidateRow(
                            person: FollowCandidate(
                              userId: literal,
                              displayName: literal,
                              avatarMxc: null,
                            ),
                            subtitle: 'Follow this id directly',
                            onTap: () => _follow(literal),
                          ),
                        for (final person in matches)
                          _CandidateRow(
                            key: ValueKey(person.userId),
                            person: person,
                            subtitle: person.userId,
                            onTap: () => _follow(person.userId),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Done', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }

  /// Stays open after following, so several people can be added in one visit.
  Future<void> _follow(String userId) async {
    await ref.read(activityPrefsProvider.notifier).follow(userId);
    if (!mounted) return;
    _controller.clear();
    setState(() => _query = '');
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    super.key,
    required this.person,
    required this.subtitle,
    required this.onTap,
  });

  final FollowCandidate person;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActivityRow(
    avatar: MxAvatar(
      name: person.displayName,
      seed: person.userId,
      mxcUri: person.avatarMxc,
      size: 28,
    ),
    title: Text(person.displayName),
    subtitle: Text(subtitle),
    trailing: Icon(Icons.add, size: 16, color: context.colors.textMuted),
    onTap: onTap,
  );
}

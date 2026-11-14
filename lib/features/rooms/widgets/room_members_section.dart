// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/room_permissions.dart';
import '../../../theme/theme_context.dart';
import '../../activity/widgets/user_context_menu.dart';
import '../../common/hoverable.dart';
import '../../common/mx_avatar.dart';
import '../../settings/widgets/settings_layout.dart';
import '../room_admin.dart';
import '../room_members.dart';
import 'room_manage_dialog.dart';

/// Who is in a room, and what can be done about each of them.
///
/// The app had no member list anywhere. People were read out of rooms to
/// complete a mention and to fill the follow list, and nowhere could somebody
/// simply see who was in the room they were looking at — which is also why
/// there was nowhere to remove anybody from.
///
/// Every action is decided before the row is drawn (`RoomMember` carries the
/// answers), so a row offers exactly what the homeserver would accept from
/// this account for that person. For most people in most rooms that is
/// nothing, and the row is then just a name.
class RoomMembersSection extends ConsumerStatefulWidget {
  const RoomMembersSection({
    super.key,
    required this.roomId,
    required this.isSpace,
    required this.busy,
    required this.run,
  });

  final String roomId;
  final bool isSpace;
  final bool busy;
  final RunChange run;

  @override
  ConsumerState<RoomMembersSection> createState() => _RoomMembersSectionState();
}

class _RoomMembersSectionState extends ConsumerState<RoomMembersSection> {
  final _search = TextEditingController();

  /// Whose actions are open. One at a time: the list is a list, and a column
  /// of expanded rows is a form.
  String? _openUserId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _noun => widget.isSpace ? 'space' : 'room';

  Future<void> _kick(RoomMember member) async {
    final confirmed = await confirmRoomChange(
      context,
      title: 'Remove ${member.name}?',
      body: member.standing == MemberStanding.invited
          ? 'Their invitation is withdrawn. They can be invited again.'
          : 'They are taken out of this $_noun. They can come back if it '
                'lets them — by invitation, or straight away if anyone can '
                'join.',
      action: 'Remove',
    );
    if (!confirmed || !mounted) return;
    await widget.run(
      () => ref.read(roomAdminProvider).kick(widget.roomId, member.userId),
      done: '${member.name} was removed.',
    );
  }

  Future<void> _ban(RoomMember member) async {
    final confirmed = await confirmRoomChange(
      context,
      title: 'Ban ${member.name}?',
      body:
          'They are taken out of this $_noun and cannot come back, by '
          'invitation or otherwise, until somebody lifts the ban.'
          '${widget.isSpace ? ' Rooms inside it are not affected — a ban '
                    'in a space is not a ban in its rooms.' : ''}',
      action: 'Ban',
    );
    if (!confirmed || !mounted) return;
    await widget.run(
      () => ref.read(roomAdminProvider).ban(widget.roomId, member.userId),
      done: '${member.name} was banned.',
    );
  }

  Future<void> _unban(RoomMember member) => widget.run(
    () => ref.read(roomAdminProvider).unban(widget.roomId, member.userId),
    done:
        'The ban on ${member.name} was lifted. They are not back in the '
        '$_noun until they rejoin or are invited.',
  );

  Future<void> _setRole(RoomMember member, RoomRole role, int ownLevel) async {
    // The two changes nobody can take back themselves. Everything else about
    // a role can be put right by the person who made it.
    if (member.isSelf) {
      final confirmed = await confirmRoomChange(
        context,
        title: 'Step down to ${role.label}?',
        body:
            'You are lowering your own role. You will not be able to raise '
            'it again yourself — somebody who still outranks you would have '
            'to.',
        action: 'Step down',
      );
      if (!confirmed || !mounted) return;
    } else if (role.level >= ownLevel) {
      final confirmed = await confirmRoomChange(
        context,
        title: 'Make ${member.name} ${_article(role.label)}?',
        body:
            'That is the same role as yours. Nobody can change the role of '
            'somebody at their own level, so you will not be able to undo '
            'this.',
        action: 'Make ${role.label}',
      );
      if (!confirmed || !mounted) return;
    }

    await widget.run(
      () => ref
          .read(roomAdminProvider)
          .setLevel(widget.roomId, member.userId, role.level),
      done: '${member.name} is now ${_article(role.label)}.',
    );
  }

  static String _article(String role) =>
      '${'aeiou'.contains(role[0].toLowerCase()) ? 'an' : 'a'} '
      '${role.toLowerCase()}';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final load = ref.watch(roomMembersLoadProvider(widget.roomId));
    final everybody = ref.watch(roomMembersProvider(widget.roomId));
    final shown = everybody.matching(_search.text);
    final ownLevel =
        ref.watch(roomAdminInfoProvider(widget.roomId))?.ownLevel ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('room_members_search'),
          controller: _search,
          style: context.text.inputText,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Find somebody by name or user ID',
            prefixIcon: Icon(Icons.search, size: 16, color: colors.textFaint),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),

        // The list is already showing whoever sync has delivered. This says
        // whether that is everybody yet, because the difference is exactly
        // the people a member list is for: the ones who never speak.
        switch (load) {
          AsyncLoading() => Text(
            'Showing who has been active — fetching the full list…',
            style: context.text.timestamp,
          ),
          AsyncError(:final error) => Text(
            'Only people who have been active are shown. The full list '
            'could not be fetched: $error',
            style: context.text.timestamp.copyWith(color: colors.warning),
          ),
          _ => Text(_count(everybody, shown), style: context.text.timestamp),
        },
        const SizedBox(height: 8),

        Expanded(
          child: shown.members.isEmpty
              ? Center(
                  child: Text(
                    _search.text.trim().isEmpty
                        ? 'Nobody to show.'
                        : 'Nobody here matches that.',
                    style: context.text.subtitle,
                  ),
                )
              : ListView(
                  children: [
                    for (final standing in MemberStanding.values)
                      if (shown.standing(standing) case final group
                          when group.isNotEmpty) ...[
                        // A heading only where there is something to tell
                        // apart. A room where everybody is simply in it does
                        // not need to be told so.
                        if (standing != MemberStanding.joined ||
                            shown.members.length != group.length)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(
                              '${standing.heading.toUpperCase()} · '
                              '${group.length}',
                              style: context.text.fieldLabel,
                            ),
                          ),
                        for (final member in group)
                          _MemberRow(
                            key: ValueKey(member.userId),
                            member: member,
                            open: _openUserId == member.userId,
                            busy: widget.busy,
                            onToggle: () => setState(
                              () => _openUserId = _openUserId == member.userId
                                  ? null
                                  : member.userId,
                            ),
                            onKick: () => _kick(member),
                            onBan: () => _ban(member),
                            onUnban: () => _unban(member),
                            onRole: (role) => _setRole(member, role, ownLevel),
                          ),
                      ],
                  ],
                ),
        ),
      ],
    );
  }

  static String _count(RoomMemberList everybody, RoomMemberList shown) {
    final total = everybody.standing(MemberStanding.joined).length;
    final people = '$total ${total == 1 ? "person" : "people"}';
    return shown.members.length == everybody.members.length
        ? '$people in here.'
        : '${shown.members.length} of ${everybody.members.length} shown.';
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.member,
    required this.open,
    required this.busy,
    required this.onToggle,
    required this.onKick,
    required this.onBan,
    required this.onUnban,
    required this.onRole,
  });

  final RoomMember member;
  final bool open;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onKick;
  final VoidCallback onBan;
  final VoidCallback onUnban;
  final ValueChanged<RoomRole> onRole;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Hoverable(
          onTap: onToggle,
          builder: (context, hovered) => Container(
            key: Key('room_member_${member.userId}'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: open || hovered ? colors.listItemHover : null,
              borderRadius: BorderRadius.circular(context.metrics.rowRadius),
            ),
            child: Row(
              children: [
                MxAvatar(
                  name: member.name,
                  seed: member.userId,
                  mxcUri: member.avatarMxc,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.isSelf ? '${member.name} (you)' : member.name,
                        style: context.text.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // The id, always. Two people can share a display name
                      // and this is the list somebody removes people from.
                      Text(
                        member.userId,
                        style: context.text.timestamp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Only said when it is not the ordinary one. A column of
                // "Member" down the side of a list is noise that hides the
                // two rows where it says something else.
                if (member.level != RoomRole.member.level &&
                    member.standing == MemberStanding.joined)
                  Text(
                    member.role,
                    style: context.text.timestamp.copyWith(
                      color: colors.accent,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 4, 8, 10),
            child: _actions(context),
          ),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (member.grantable.isNotEmpty) ...[
          Text('ROLE', style: context.text.fieldLabel),
          const SizedBox(height: 6),
          IgnorePointer(
            ignoring: busy,
            child: SettingsChoice<RoomRole?>(
              // Their current role among the ones on offer, so the row reads
              // as "this, and it could be that" rather than as a list of
              // things they are not.
              values: [
                for (final role in RoomRole.values)
                  if (role.level == member.level ||
                      member.grantable.contains(role))
                    role,
              ],
              selected: RoomRole.at(member.level),
              labelOf: (role) => role!.label,
              onChanged: (role) {
                if (role != null && role.level != member.level) onRole(role);
              },
            ),
          ),
          if (RoomRole.at(member.level) == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Currently ${member.role}, a level another client set.',
                style: context.text.timestamp,
              ),
            ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: () => UserContextMenu.show(
                context,
                userId: member.userId,
                displayName: member.name,
                avatarMxc: member.avatarMxc,
              ),
              icon: const Icon(Icons.person_outline, size: 16),
              label: const Text('Profile'),
            ),
            if (member.canKick)
              OutlinedButton.icon(
                key: Key('room_member_kick_${member.userId}'),
                onPressed: busy ? null : onKick,
                icon: Icon(
                  Icons.person_remove_outlined,
                  size: 16,
                  color: colors.danger,
                ),
                label: Text(
                  member.standing == MemberStanding.invited
                      ? 'Withdraw invitation'
                      : 'Remove',
                  style: TextStyle(color: colors.danger),
                ),
              ),
            if (member.canBan)
              OutlinedButton.icon(
                key: Key('room_member_ban_${member.userId}'),
                onPressed: busy ? null : onBan,
                icon: Icon(Icons.block, size: 16, color: colors.danger),
                label: Text('Ban', style: TextStyle(color: colors.danger)),
              ),
            if (member.canUnban)
              OutlinedButton.icon(
                key: Key('room_member_unban_${member.userId}'),
                onPressed: busy ? null : onUnban,
                icon: const Icon(Icons.lock_open, size: 16),
                label: const Text('Lift ban'),
              ),
          ],
        ),
        // Said rather than left as an absence, for the person who opened a
        // row expecting to be able to do something.
        if (!member.hasActions && !member.isSelf)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              member.standing == MemberStanding.joined
                  ? 'You cannot remove them or change their role: that '
                        'needs a role above theirs.'
                  : 'There is nothing you can change here.',
              style: context.text.timestamp,
            ),
          ),
      ],
    );
  }
}

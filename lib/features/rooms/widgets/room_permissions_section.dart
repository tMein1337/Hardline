// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/room_permissions.dart';
import '../../../theme/theme_context.dart';
import '../../settings/widgets/settings_layout.dart';
import '../room_admin.dart';
import 'room_manage_dialog.dart';

/// Which role each kind of action needs.
///
/// Readable by everybody in the room and changeable by very few, and it is
/// worth showing to the many: "why can I not rename this" has an answer, and
/// this is where it is.
///
/// Each row is checked on its own. Being allowed to edit permissions is not
/// being allowed to edit all of them — an entry already above somebody's own
/// role is out of their reach, and nobody can set one higher than they hold.
/// A moderator given the right to change permissions sees the admin-only rows
/// as text and the rest as controls with Admin missing.
class RoomPermissionsSection extends ConsumerWidget {
  const RoomPermissionsSection({
    super.key,
    required this.roomId,
    required this.info,
    required this.busy,
    required this.run,
  });

  final String roomId;
  final RoomAdminInfo info;
  final bool busy;
  final RunChange run;

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    RoomPermission permission,
    RoomRole role,
  ) async {
    // The one row that can lock its own door. Raising what changing
    // permissions needs to above your own role is refused by the server;
    // lowering it to Member is accepted, and hands the whole page to everybody.
    if (permission == RoomPermission.permissions && role == RoomRole.member) {
      final confirmed = await confirmRoomChange(
        context,
        title: 'Let every member change permissions?',
        body:
            'Anybody in here could then change every setting on this page, '
            'and give themselves any role up to their own. That is rarely '
            'what is meant.',
        action: 'Let them',
      );
      if (!confirmed) return;
    }

    await run(
      () => ref
          .read(roomAdminProvider)
          .setPermission(roomId, permission, role.level),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          info.canChangePermissions
              ? 'Your role here is ${roleLabel(info.ownLevel)}. You can '
                    'change what your role or a lower one is needed for.'
              : 'Your role here is ${roleLabel(info.ownLevel)}. These are '
                    'who may do what; changing them needs '
                    '${roleLabel(info.permissions[RoomPermission.permissions] ?? 100)}.',
          style: context.text.subtitle,
        ),
        const SizedBox(height: 12),
        for (final entry in info.permissions.entries) ...[
          _PermissionRow(
            permission: entry.key,
            level: entry.value,
            // The roles this account could set this row to. Empty means the
            // row is out of reach altogether.
            settable: [
              for (final role in RoomRole.values)
                if (info.canSetPermission(entry.key, role.level)) role,
            ],
            busy: busy,
            onChanged: (role) => _set(context, ref, entry.key, role),
          ),
          Divider(height: 20, color: colors.divider),
        ],
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.permission,
    required this.level,
    required this.settable,
    required this.busy,
    required this.onChanged,
  });

  final RoomPermission permission;
  final int level;
  final List<RoomRole> settable;
  final bool busy;
  final ValueChanged<RoomRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = RoomRole.at(level);

    return Column(
      key: Key('room_permission_${permission.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(permission.label, style: context.text.username),
            ),
            // Always in words as well, so a row that cannot be changed still
            // says what it is set to, and a level between the named ones is
            // not shown as a control with nothing selected and no reason.
            if (settable.isEmpty || current == null)
              Text(roleLabel(level), style: context.text.subtitle),
          ],
        ),
        if (permission.detail case final detail?) ...[
          const SizedBox(height: 2),
          Text(detail, style: context.text.timestamp),
        ],
        if (settable.isNotEmpty) ...[
          const SizedBox(height: 6),
          IgnorePointer(
            ignoring: busy,
            child: SettingsChoice<RoomRole?>(
              values: settable,
              selected: current,
              labelOf: (role) => role!.label,
              onChanged: (role) {
                if (role != null && role != current) onChanged(role);
              },
            ),
          ),
        ],
      ],
    );
  }
}

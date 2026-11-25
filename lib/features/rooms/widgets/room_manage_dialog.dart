// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../../common/app_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' show HistoryVisibility;

import '../../../core/providers/injected_providers.dart';
import '../../../theme/theme_context.dart';
import '../../activity/widgets/user_context_menu.dart';
import '../../chat/attachments/attachment_picker_source.dart';
import '../../common/mx_avatar.dart';
import '../../settings/widgets/settings_layout.dart';
import '../../shell/selection_providers.dart';
import '../../spaces/space_hierarchy_provider.dart';
import '../../spaces/space_summary.dart';
import '../../spaces/widgets/invite_people_dialog.dart';
import '../room_admin.dart';
import 'room_members_section.dart';
import 'room_permissions_section.dart';

/// The three pages of the dialog.
enum RoomManageSection {
  settings('Settings'),
  members('Members'),
  permissions('Permissions');

  const RoomManageSection(this.label);

  final String label;
}

/// Runs one change against the homeserver and reports how it went.
///
/// What every page of the dialog is handed instead of a way to set state on
/// it. [done] is what to say when it worked; null says nothing, for a change
/// whose result is already on screen.
typedef RunChange =
    Future<bool> Function(Future<void> Function() change, {String? done});

/// Picks an image for a room's picture. Null when the user cancels.
///
/// A provider so a test can answer without a file dialog, which a test has
/// no way to click.
final roomAvatarPickerProvider = Provider<Future<String?> Function()>(
  (ref) => pickImagePath,
);

/// What right-clicking a room in the list, or a space on the rail, opens.
///
/// One dialog for both because a space *is* a room — the differences are which
/// sections apply, not what the thing is. Two dialogs would have meant two
/// copies of a destructive routine drifting apart.
///
/// Everything here is gated on what the homeserver would actually accept, so
/// somebody with no power sees their way out and nothing else. A control that
/// fails on the click reads as the app being broken rather than as a
/// permission they do not have.
///
/// A direct chat is the one shape that gets a different answer rather than a
/// smaller one: it is really a person, so it offers the person.
class RoomManageDialog extends ConsumerStatefulWidget {
  const RoomManageDialog({
    super.key,
    required this.roomId,
    this.initialSection = RoomManageSection.settings,
  });

  final String roomId;
  final RoomManageSection initialSection;

  static Future<void> show(
    BuildContext context,
    String roomId, {
    RoomManageSection section = RoomManageSection.settings,
  }) => showDialog(
    context: context,
    builder: (_) => RoomManageDialog(roomId: roomId, initialSection: section),
  );

  @override
  ConsumerState<RoomManageDialog> createState() => _RoomManageDialogState();
}

class _RoomManageDialogState extends ConsumerState<RoomManageDialog> {
  final _name = TextEditingController();
  final _topic = TextEditingController();

  late RoomManageSection _section = widget.initialSection;

  /// Seeded once. Re-seeding on every rebuild would fight the cursor, since
  /// the info provider recomputes on every sync tick.
  bool _seeded = false;

  bool _busy = false;
  String? _error;
  String? _saved;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  /// Makes one change, with the dialog locked while it is in flight.
  ///
  /// The one place a request is made from this dialog and its pages, so there
  /// is one place that decides what "busy" disables and how a refusal reads.
  Future<bool> _run(Future<void> Function() change, {String? done}) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
      _saved = null;
    });
    try {
      await change();
      if (mounted) setState(() => _saved = done);
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(RoomAdminInfo info) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(
        () => _error = 'A ${info.isSpace ? "space" : "room"} needs a name.',
      );
      return;
    }

    await _run(() async {
      final admin = ref.read(roomAdminProvider);
      // Only what changed. Each is a state event and a round trip, and
      // rewriting a topic nobody touched would put a pointless entry in
      // everybody's timeline.
      if (name != info.name) await admin.rename(widget.roomId, name);
      if (_topic.text.trim() != info.topic) {
        await admin.setTopic(widget.roomId, _topic.text.trim());
      }
    }, done: 'Saved.');
  }

  Future<void> _changePicture() async {
    final path = await ref.read(roomAvatarPickerProvider)();
    if (path == null || !mounted) return;
    await _run(
      () => ref.read(roomAdminProvider).setAvatarFromPath(widget.roomId, path),
      done: 'Picture changed.',
    );
  }

  Future<void> _removeFromSpace(RoomAdminInfo info, RoomParent parent) async {
    final noun = info.isSpace ? 'space' : 'room';
    final confirmed = await _confirm(
      title: 'Take it out of ${parent.name}?',
      body:
          'The $noun itself is not touched: everybody stays in it and nothing '
          'in it is deleted. It just stops being listed in ${parent.name}, '
          'for everyone who can see that space.',
      action: 'Take out',
    );
    if (!confirmed || !mounted) return;

    await _run(() async {
      await ref
          .read(roomAdminProvider)
          .removeFromSpace(parent.id, widget.roomId);
      ref.invalidate(spaceHierarchyProvider(parent.id));
    }, done: 'Taken out of ${parent.name}.');
  }

  Future<void> _joinClaimedParent(ClaimedParent parent) => _run(() async {
    await ref.read(clientProvider).joinRoom(parent.id, via: parent.via);
  }, done: 'Joined. It will appear on the rail.');

  Future<void> _leave(RoomAdminInfo info) async {
    final confirmed = await _confirm(
      title: info.isDirect
          ? 'Leave this chat?'
          : 'Leave this ${info.isSpace ? "space" : "room"}?',
      body: info.isDirect
          ? 'The conversation stays with them, and they can message you '
                'again. In an encrypted chat you may not be able to read the '
                'history if you come back.'
          : 'It stays where it is for everybody else, and you can come back '
                'if somebody invites you'
                '${info.alias.isEmpty ? "" : " or through its address"}.',
      action: 'Leave',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(roomAdminProvider).leave(widget.roomId);
      if (!mounted) return;
      _closeAndGoHome();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _describe(error);
        });
      }
    }
  }

  Future<void> _delete(RoomAdminInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmation(info: info),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final problems = await ref
          .read(roomAdminProvider)
          .dismantle(
            widget.roomId,
            onStep: (step) {
              if (mounted) setState(() => _saved = '${step.label}…');
            },
          );
      if (!mounted) return;

      if (problems.isEmpty) {
        _closeAndGoHome();
        return;
      }

      // Gone from this account either way — the leave at the end succeeded or
      // the whole thing threw. What is left to say is which parts the server
      // refused, and that is worth showing rather than swallowing.
      final messenger = ScaffoldMessenger.maybeOf(context);
      _closeAndGoHome();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '${info.isSpace ? "Space" : "Room"} removed, but '
            '${problems.length} '
            '${problems.length == 1 ? "part" : "parts"} could not be '
            'completed. ${problems.first}',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _describe(error);
        });
      }
    }
  }

  void _closeAndGoHome() {
    Navigator.of(context).pop();
    // The rail entry is about to disappear; leaving it selected would show an
    // empty column with nothing to explain it.
    ref.read(selectedSpaceIdProvider.notifier).select(kHomeSpaceId);
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) => confirmRoomChange(context, title: title, body: body, action: action);

  /// The line under the name: how many people, and what it contains.
  static String _summary(RoomAdminInfo info) {
    final members =
        '${info.memberCount} '
        '${info.memberCount == 1 ? "member" : "members"}';
    if (!info.isSpace) return members;
    return '$members · ${info.childCount} '
        '${info.childCount == 1 ? "room" : "rooms"}';
  }

  String _describe(Object error) {
    final text = error.toString();
    if (text.contains('M_FORBIDDEN')) {
      return 'The homeserver refused that — you may not have permission.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = ref.watch(roomAdminInfoProvider(widget.roomId));

    if (info == null) {
      return AlertDialog(
        backgroundColor: colors.floatingSurface,
        content: Text(
          'That room is no longer here.',
          style: context.text.messageBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    if (!_seeded) {
      _seeded = true;
      _name.text = info.name;
      _topic.text = info.topic;
    }

    // A direct chat has two people in it and nothing to configure: no member
    // list worth the name, and permissions between two people who both hold
    // all of them. It keeps the one page it always had.
    final sections = info.isDirect
        ? const [RoomManageSection.settings]
        : RoomManageSection.values;
    final section = sections.contains(_section)
        ? _section
        : RoomManageSection.settings;

    // As tall as the window allows and no taller than it needs. The member
    // list scrolls inside whatever this comes to.
    final height = (MediaQuery.sizeOf(context).height - 280).clamp(
      220.0,
      560.0,
    );

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Row(
        children: [
          MxAvatar(
            name: info.name,
            seed: widget.roomId,
            mxcUri: info.avatarMxc,
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  info.name,
                  style: context.text.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _summary(info),
                        style: context.text.timestamp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (info.isEncrypted) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock, size: 11, color: colors.textFaint),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sections.length > 1) ...[
              SettingsChoice<RoomManageSection>(
                values: sections,
                selected: section,
                labelOf: (value) => value.label,
                onChanged: (value) => setState(() {
                  _section = value;
                  // What one page said about its last change is not about
                  // the page being turned to.
                  _error = null;
                  _saved = null;
                }),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: switch (section) {
                RoomManageSection.settings => SingleChildScrollView(
                  child: _settings(context, info),
                ),
                RoomManageSection.members => RoomMembersSection(
                  roomId: widget.roomId,
                  isSpace: info.isSpace,
                  busy: _busy,
                  run: _run,
                ),
                RoomManageSection.permissions => SingleChildScrollView(
                  child: RoomPermissionsSection(
                    roomId: widget.roomId,
                    info: info,
                    busy: _busy,
                    run: _run,
                  ),
                ),
              },
            ),
            if (_saved case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                key: const Key('room_manage_saved'),
                style: context.text.timestamp.copyWith(color: colors.success),
              ),
            ],
            if (_error case final message?) ...[
              const SizedBox(height: 8),
              Text(
                message,
                key: const Key('room_manage_error'),
                style: context.text.timestamp.copyWith(color: colors.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Close', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }

  Widget _settings(BuildContext context, RoomAdminInfo info) {
    final colors = context.colors;
    final noun = info.isSpace ? 'space' : 'room';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (info.alias.isNotEmpty) _Address(alias: info.alias),

        for (final parent in info.parents)
          _ParentRow(
            parent: parent,
            onRemove: _busy ? null : () => _removeFromSpace(info, parent),
          ),
        for (final parent in info.claimedParents)
          _ClaimedParentRow(
            parent: parent,
            onJoin: _busy ? null : () => _joinClaimedParent(parent),
          ),

        // A direct chat is a person before it is a room. Renaming one is
        // possible and almost never what anybody means, so the person is
        // offered instead of the name and topic fields.
        if (info.isDirect && info.directUserId != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                UserContextMenu.show(
                  context,
                  userId: info.directUserId!,
                  displayName: info.name,
                  avatarMxc: info.avatarMxc,
                );
              },
              icon: const Icon(Icons.person_outline, size: 18),
              label: Text('About ${info.name}'),
            ),
          ),
        ] else ...[
          if (info.canSetAvatar) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const Key('room_manage_picture'),
                  onPressed: _busy ? null : _changePicture,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(
                    info.avatarMxc == null ? 'Add a picture' : 'Change picture',
                  ),
                ),
                if (info.avatarMxc != null) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref
                                .read(roomAdminProvider)
                                .removeAvatar(widget.roomId),
                            done: 'Picture removed.',
                          ),
                    child: Text(
                      'Remove',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (info.canDescribe) ...[
            const SizedBox(height: 12),
            TextField(
              key: const Key('room_manage_name'),
              controller: _name,
              enabled: !_busy,
              style: context.text.inputText,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('room_manage_topic'),
              controller: _topic,
              enabled: !_busy,
              maxLines: 3,
              style: context.text.inputText,
              decoration: const InputDecoration(labelText: 'Topic'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('room_manage_save'),
                onPressed: _busy ? null : () => _save(info),
                child: const Text('Save'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              info.topic.isEmpty
                  ? 'You cannot change this $noun\'s name or topic.'
                  : info.topic,
              style: context.text.subtitle,
            ),
          ],

          const SizedBox(height: 16),
          _AccessSetting(
            roomId: widget.roomId,
            info: info,
            busy: _busy,
            run: _run,
          ),

          // A space holds no conversation, so there is no history for
          // anybody to be shown or not shown.
          if (!info.isSpace) ...[
            const SizedBox(height: 16),
            _HistorySetting(
              roomId: widget.roomId,
              info: info,
              busy: _busy,
              run: _run,
            ),
          ],

          if (info.canPublish) ...[
            const SizedBox(height: 8),
            _DirectorySetting(roomId: widget.roomId, busy: _busy, run: _run),
          ],
        ],

        if (info.canInvite) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => InvitePeopleDialog.show(
                      context,
                      roomId: widget.roomId,
                      roomName: info.name,
                      isSpace: info.isSpace,
                    ),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Invite people'),
            ),
          ),
        ],

        const SizedBox(height: 16),
        Divider(color: colors.divider),
        const SizedBox(height: 8),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : () => _leave(info),
            icon: Icon(Icons.logout, size: 18, color: colors.textMuted),
            label: Text(
              info.isDirect ? 'Leave chat' : 'Leave $noun',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
        ),
        if (info.canDismantle)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _delete(info),
              icon: Icon(Icons.delete_outline, size: 18, color: colors.danger),
              label: Text(
                'Delete $noun',
                style: TextStyle(color: colors.danger),
              ),
            ),
          ),
      ],
    );
  }
}

/// Asks before something that changes the room for other people.
///
/// Shared by the dialog's pages, so the question looks the same wherever it
/// is asked from.
Future<bool> confirmRoomChange(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final colors = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text(title, style: context.text.title),
      content: SizedBox(
        width: 400,
        child: Text(body, style: context.text.messageBody),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action, style: TextStyle(color: colors.danger)),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _Address extends StatelessWidget {
  const _Address({required this.alias});

  final String alias;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Flexible(
          child: Text(
            alias,
            style: context.text.timestamp,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: 'Copy address',
          iconSize: 14,
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.copy_all_outlined, color: colors.textFaint),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: alias));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(const SnackBar(content: Text('Address copied.')));
          },
        ),
      ],
    );
  }
}

/// One space this room is filed under, with the way out of it.
class _ParentRow extends StatelessWidget {
  const _ParentRow({required this.parent, required this.onRemove});

  final RoomParent parent;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Icon(Icons.folder_outlined, size: 14, color: colors.textFaint),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'In ${parent.name}',
            style: context.text.timestamp,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Only when this account can write to that space. It is not a
        // question about the room being looked at, which is why somebody who
        // runs the room may still not see this.
        if (parent.canRemove)
          TextButton(
            key: Key('room_manage_detach_${parent.id}'),
            onPressed: onRemove,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(
              'Take out',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: context.text.sized(12),
              ),
            ),
          ),
      ],
    );
  }
}

/// A space the room names as its parent, which this account is not in.
class _ClaimedParentRow extends StatelessWidget {
  const _ClaimedParentRow({required this.parent, required this.onJoin});

  final ClaimedParent parent;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      children: [
        Icon(Icons.folder_off_outlined, size: 14, color: colors.textFaint),
        const SizedBox(width: 6),
        Expanded(
          child: AppTooltip(
            // Worded as the room's claim, because that is all it is: nothing
            // here can check the space lists it back without being in it.
            message:
                'This room says it belongs to ${parent.id}. Whether that '
                'space agrees can only be seen from inside it.',
            child: Text(
              'Says it is part of a space you are not in',
              style: context.text.timestamp,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        TextButton(
          key: Key('room_manage_join_parent_${parent.id}'),
          onPressed: onJoin,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: Text(
            'Join it',
            style: TextStyle(
              color: colors.accent,
              fontSize: context.text.sized(12),
            ),
          ),
        ),
      ],
    );
  }
}

/// A heading, a line saying what the setting is now, and the choices.
///
/// The shape both the access and the history setting take. Somebody without
/// the permission sees the first two and none of the third — the setting is
/// still worth knowing, and a row of dead buttons says less than a sentence.
class _ChoiceSetting<T> extends StatelessWidget {
  const _ChoiceSetting({
    super.key,
    required this.heading,
    required this.current,
    required this.detail,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String heading;

  /// What it is set to, in words. Shown when it cannot be changed, and when
  /// it is something that is not among [options].
  final String current;

  /// What the current setting means for somebody.
  final String? detail;

  /// Empty when this account cannot change it.
  final List<T> options;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading.toUpperCase(), style: context.text.fieldLabel),
        const SizedBox(height: 6),
        if (options.isEmpty || selected == null) ...[
          Text(current, style: context.text.subtitle),
          const SizedBox(height: 6),
        ],
        if (options.isNotEmpty)
          IgnorePointer(
            ignoring: onChanged == null,
            child: Opacity(
              opacity: onChanged == null ? 0.5 : 1,
              child: SettingsChoice<T?>(
                values: options,
                selected: selected,
                labelOf: (value) => labelOf(value as T),
                onChanged: (value) {
                  if (value == null || value == selected) return;
                  onChanged?.call(value);
                },
              ),
            ),
          ),
        if (detail case final text?) ...[
          const SizedBox(height: 6),
          Text(text, style: context.text.timestamp),
        ],
      ],
    );
  }
}

class _AccessSetting extends ConsumerWidget {
  const _AccessSetting({
    required this.roomId,
    required this.info,
    required this.busy,
    required this.run,
  });

  final String roomId;
  final RoomAdminInfo info;
  final bool busy;
  final RunChange run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = RoomAccess.of(info.joinRule);

    return _ChoiceSetting<RoomAccess>(
      key: const Key('room_manage_access'),
      heading: 'Who can join',
      current: describeJoinRule(info.joinRule),
      detail: current?.detail,
      options: info.canChangeAccess
          ? [
              RoomAccess.inviteOnly,
              // Offered when there is a space to refer to — and kept on show
              // when it is what the room is already set to, or the selection
              // would vanish from under somebody who had it.
              if (info.canRestrictToSpace || current == RoomAccess.spaceMembers)
                RoomAccess.spaceMembers,
              RoomAccess.public,
            ]
          : const [],
      selected: current,
      labelOf: (access) => access.label,
      onChanged: busy
          ? null
          : (access) => run(
              () => ref
                  .read(roomAdminProvider)
                  .setAccess(
                    roomId,
                    access,
                    throughSpaceIds: [
                      for (final parent in info.parents) parent.id,
                    ],
                  ),
            ),
    );
  }
}

class _HistorySetting extends ConsumerWidget {
  const _HistorySetting({
    required this.roomId,
    required this.info,
    required this.busy,
    required this.run,
  });

  final String roomId;
  final RoomAdminInfo info;
  final bool busy;
  final RunChange run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Unset is not "nothing": homeservers treat a room with no such event as
    // `shared`, so that is what is shown as selected.
    final current = info.history ?? HistoryVisibility.shared;

    return _ChoiceSetting<HistoryVisibility>(
      key: const Key('room_manage_history'),
      heading: 'What new members can read',
      current: current.label,
      detail: current.detail,
      options: info.canChangeHistory
          ? const [
              HistoryVisibility.shared,
              HistoryVisibility.invited,
              HistoryVisibility.joined,
              HistoryVisibility.worldReadable,
            ]
          : const [],
      selected: current,
      labelOf: (visibility) => visibility.label,
      onChanged: busy
          ? null
          : (visibility) => run(
              () => ref.read(roomAdminProvider).setHistory(roomId, visibility),
            ),
    );
  }
}

/// Whether the room is in the homeserver's public directory.
class _DirectorySetting extends ConsumerWidget {
  const _DirectorySetting({
    required this.roomId,
    required this.busy,
    required this.run,
  });

  final String roomId;
  final bool busy;
  final RunChange run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listed = ref.watch(roomListedProvider(roomId));

    // Nothing until the homeserver has answered. A switch drawn off and then
    // flipped on a moment later is a switch somebody has already clicked.
    return switch (listed) {
      AsyncData(:final value) => SettingsSwitchTile(
        key: const Key('room_manage_listed'),
        contentPadding: EdgeInsets.zero,
        value: value,
        title: 'Listed in this homeserver\'s directory',
        subtitle: value
            ? 'Anybody browsing the directory can find it. Who can then join '
                  'is the setting above.'
            : 'It can only be reached by address, or by invitation.',
        onChanged: busy
            ? null
            : (next) async {
                await run(
                  () => ref.read(roomAdminProvider).setListed(roomId, next),
                );
                ref.invalidate(roomListedProvider(roomId));
              },
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// The confirmation for taking a space apart.
///
/// Says what will and will not happen, because "delete" promises more than
/// Matrix can deliver and somebody should not find that out afterwards. The
/// name has to be typed: this cannot be undone, it affects everybody else in
/// the space, and a misplaced click should not be enough.
class _DeleteConfirmation extends StatefulWidget {
  const _DeleteConfirmation({required this.info});

  final RoomAdminInfo info;

  @override
  State<_DeleteConfirmation> createState() => _DeleteConfirmationState();
}

class _DeleteConfirmationState extends State<_DeleteConfirmation> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final info = widget.info;
    final matches = _typed.text.trim() == info.name;

    return AlertDialog(
      backgroundColor: colors.floatingSurface,
      title: Text('Delete ${info.name}?', style: context.text.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('This will:', style: context.text.messageBody),
            const SizedBox(height: 6),
            if (info.isSpace)
              _Point(
                text:
                    'Release its ${info.childCount} '
                    '${info.childCount == 1 ? "room" : "rooms"}. They are not '
                    'deleted — anybody in one keeps it, in their Home list.',
              )
            else if (info.parentNames.isNotEmpty)
              _Point(
                text:
                    'Remove it from ${info.parentNames.join(", ")}, if you '
                    'have permission there. If not, it stays listed for '
                    'whoever can see that space and this will say so.',
              ),
            if (info.alias.isNotEmpty)
              _Point(
                text:
                    'Remove the address ${info.alias}, so nobody can find or '
                    'join it.',
              ),
            _Point(
              text:
                  'Remove the other '
                  '${info.memberCount <= 1 ? "members" : "${info.memberCount - 1} members"}.',
            ),
            _Point(text: 'Remove it from your account.'),
            const SizedBox(height: 12),
            // The part every "delete room" button in every Matrix client is
            // quietly wrong about.
            Text(
              'It will not erase the ${info.isSpace ? "space" : "room"} from '
              'the servers that have seen it, and it will not delete the '
              'messages in it. Matrix has no way for any client to do either '
              '— what this does is make it unreachable and empty.',
              style: context.text.timestamp.copyWith(color: colors.warning),
            ),
            const SizedBox(height: 16),
            Text('Type the name to confirm.', style: context.text.subtitle),
            const SizedBox(height: 6),
            TextField(
              controller: _typed,
              autofocus: true,
              style: context.text.inputText,
              decoration: InputDecoration(hintText: info.name),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (matches) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: colors.danger),
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('· ', style: context.text.subtitle),
        Expanded(child: Text(text, style: context.text.subtitle)),
      ],
    ),
  );
}

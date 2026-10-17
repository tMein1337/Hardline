// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/theme_context.dart';
import '../../common/mx_avatar.dart';
import '../../activity/widgets/user_context_menu.dart';
import '../../shell/selection_providers.dart';
import '../room_admin.dart';
import '../../spaces/space_summary.dart';
import '../../spaces/widgets/invite_people_dialog.dart';

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
  const RoomManageDialog({super.key, required this.roomId});

  final String roomId;

  static Future<void> show(BuildContext context, String roomId) => showDialog(
    context: context,
    builder: (_) => RoomManageDialog(roomId: roomId),
  );

  @override
  ConsumerState<RoomManageDialog> createState() => _RoomManageDialogState();
}

class _RoomManageDialogState extends ConsumerState<RoomManageDialog> {
  final _name = TextEditingController();
  final _topic = TextEditingController();

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

  Future<void> _save(RoomAdminInfo info) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'A space needs a name.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _saved = null;
    });

    try {
      final admin = ref.read(roomAdminProvider);
      // Only what changed. Each is a state event and a round trip, and
      // rewriting a topic nobody touched would put a pointless entry in
      // everybody's timeline.
      if (name != info.name) await admin.rename(widget.roomId, name);
      if (_topic.text.trim() != info.topic) {
        await admin.setTopic(widget.roomId, _topic.text.trim());
      }
      if (mounted) setState(() => _saved = 'Saved.');
    } catch (error) {
      if (mounted) setState(() => _error = _describe(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      _closeAndGoHome();
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Space removed, but ${problems.length} '
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
  }) async {
    final colors = context.colors;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.floatingSurface,
        title: Text(title, style: context.text.title),
        content: Text(body, style: context.text.messageBody),
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
          'That space is no longer here.',
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
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (info.alias.isNotEmpty) _Address(alias: info.alias),

              if (info.parentNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'In ${info.parentNames.join(", ")}',
                  style: context.text.timestamp,
                ),
              ],

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
              ] else if (info.canDescribe) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  style: context.text.inputText,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
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
                    onPressed: _busy ? null : () => _save(info),
                    child: const Text('Save'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  info.topic.isEmpty
                      ? 'You cannot change this space here.'
                      : info.topic,
                  style: context.text.subtitle,
                ),
              ],

              if (info.canInvite) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => InvitePeopleDialog.show(
                            context,
                            roomId: widget.roomId,
                            roomName: info.name,
                            isSpace: true,
                          ),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Invite people'),
                  ),
                ),
              ],

              if (_saved case final message?) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  style: context.text.timestamp.copyWith(color: colors.success),
                ),
              ],
              if (_error case final message?) ...[
                const SizedBox(height: 10),
                Text(
                  message,
                  style: context.text.timestamp.copyWith(color: colors.danger),
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
                    info.isDirect
                        ? 'Leave chat'
                        : 'Leave ${info.isSpace ? "space" : "room"}',
                    style: TextStyle(color: colors.textMuted),
                  ),
                ),
              ),
              if (info.canDismantle)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _delete(info),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: colors.danger,
                    ),
                    label: Text(
                      'Delete ${info.isSpace ? "space" : "room"}',
                      style: TextStyle(color: colors.danger),
                    ),
                  ),
                ),
            ],
          ),
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
